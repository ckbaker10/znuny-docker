#!/usr/bin/env python3
"""Run README backup migrations with synthetic data and rootless Podman.

Usage: python3 tests/migration/run.py --case 7.1.3 --storage ArticleStorageFS
All runtime data and logs remain under ignored work/. Only our projects are
removed. Images and backups remain for reproducibility. No external mail/IdP.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time
import urllib.parse
import urllib.request
import http.cookiejar

REPO = Path(__file__).resolve().parents[2]


class Run:
    def __init__(self, version, storage, port, target, target_image):
        self.version, self.storage, self.port = version, storage, port
        self.target, self.target_image = target, target_image
        self.root = REPO / 'work' / f'migration-{version}-{storage}-{int(time.time())}'
        self.root.mkdir(mode=0o700, parents=True)
        self.projects = []
        self.seq = 0
        self.readme = (REPO / 'README.md').read_text()
        self.blocks = re.findall(r'```bash\n(.*?)\n```', self.readme, re.S)

    def command(self, args, cwd=None, stdin=None):
        self.seq += 1
        result = subprocess.run(args, cwd=cwd, input=stdin, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (self.root / f'{self.seq:03d}.log').write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(f'Command failed (exit {result.returncode}); see {self.root}/{self.seq:03d}.log')
        return result.stdout

    def prepare(self, name, version):
        path = self.root / name
        path.mkdir()
        project = f'znuny-migration-{os.getpid()}-{name}'
        compose = (REPO / 'docker-compose.yml').read_text().replace('image: mariadb:10.11', 'image: docker.io/library/mariadb:10.11')
        (path / 'docker-compose.yml').write_text(compose)
        image = self.target_image if version == self.target else f'localhost/znuny-migration-test:{version}'
        (path / 'override.yml').write_text(f'services:\n  znuny:\n    image: {image}\n')
        env = (REPO / '.env.example').read_text()
        for key, value in {'ZNUNY_VERSION': version, 'ZNUNY_HTTP_PORT': str(self.port),
                           'ZNUNY_BACKUP_TIME': 'disable', 'ZNUNY_DISABLE_EMAIL_FETCH': 'yes',
                           'ZNUNY_ARTICLE_STORAGE_TYPE': self.storage,
                           'ZNUNY_HOSTNAME': 'fixture.example.invalid'}.items():
            env = re.sub(rf'^{key}=.*$', f'{key}={value}', env, flags=re.M)
        env += f'\nZNUNY_ROOT_PASSWORD={self.password}\n'
        (path / '.env').write_text(env)
        for volume in ['config', 'article', 'backups', 'addons', 'mysql']:
            (path / 'volumes' / volume).mkdir(parents=True)
        self.projects.append((path, project))
        return path, project

    def compose(self, stack, *args):
        path, project = stack
        return self.command(['podman-compose', '-p', project, '-f', 'docker-compose.yml',
                             '-f', 'override.yml', *args], cwd=path)

    def cid(self, stack):
        return self.command(['podman', 'ps', '-q', '--filter',
                             f'label=com.docker.compose.project={stack[1]}', '--filter',
                             'label=com.docker.compose.service=znuny']).strip()

    def exec(self, stack, script):
        return self.command(['podman', 'exec', self.cid(stack), 'su', '-s', '/bin/bash',
                             '-c', 'cd /opt/znuny && ' + script, 'znuny'])

    def fixture(self, stack, mode):
        output = self.command(['podman', 'exec', '-i', self.cid(stack), 'su', '-s', '/bin/bash',
                               '-c', f'cd /opt/znuny && perl -I. -IKernel/cpan-lib - {mode}', 'znuny'],
                              stdin=(REPO / 'tests/migration/fixture.pl').read_text())
        return json.loads(output.strip().splitlines()[-1])

    def ready(self, stack, version):
        deadline = time.time() + 600
        while time.time() < deadline:
            cid = self.cid(stack)
            if cid:
                logs = self.command(['podman', 'logs', cid])
                if f'Znuny {version} is ready.' in logs:
                    return
            time.sleep(5)
        raise RuntimeError('Startup timeout')

    def login(self):
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        url = f'http://127.0.0.1:{self.port}/znuny/index.pl'
        opener.open(url, timeout=30).read()
        data = urllib.parse.urlencode({'Action': 'Login', 'User': 'root@localhost',
                                       'Password': self.password}).encode()
        opener.open(url, data, timeout=30).read()
        body = opener.open(url, timeout=30).read()
        if b'Action=Logout' not in body:
            raise RuntimeError('Preserved admin login failed')

    def stage(self, stack, selector):
        block = next(b for b in self.blocks if selector in b)
        # Execute the README block verbatim except for the host's container engine
        # and isolated Compose file/project selection. No app entrypoint is run.
        alias = 'docker() { shift; podman-compose -p "$MIGRATION_PROJECT" -f docker-compose.yml -f override.yml "$@"; }; export -f docker\n'
        env = os.environ.copy()
        env['MIGRATION_PROJECT'] = stack[1]
        self.seq += 1
        result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', alias + block],
                                cwd=stack[0], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=600)
        (self.root / f'{self.seq:03d}-stage.log').write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(f'README stage failed; see {self.root}/{self.seq:03d}-stage.log')
        if 'MigrateToZnuny' in block and 'Migration completed!' not in result.stdout:
            raise RuntimeError('Missing successful migration completion')

    def run(self):
        self.password = secrets.token_hex(16)
        print(f'Artifacts: {self.root}', flush=True)
        source = self.prepare('source', self.version)
        print('Starting synthetic source', flush=True)
        self.compose(source, 'up', '-d')
        self.ready(source, self.version)
        self.login()
        before = self.fixture(source, 'create')
        if not before['storage_backend'].endswith(self.storage):
            raise RuntimeError('Source used the wrong attachment storage backend')
        (self.root / 'source-fixture.json').write_text(json.dumps(before, indent=2) + '\n')
        self.exec(source, 'bin/Cron.sh stop && bin/znuny.Daemon.pl stop')
        self.command(['podman', 'exec', self.cid(source), 'supervisorctl', 'stop', 'apache2'])
        self.command(['podman', 'exec', self.cid(source), 'bash', '-c',
                      'mkdir -p /var/znuny/backups/source && chown znuny:www-data /var/znuny/backups/source'])
        self.exec(source, 'scripts/backup.pl -d /var/znuny/backups/source -t fullbackup -c gzip')
        self.compose(source, 'down')
        print('Source backed up and stopped; preparing empty target', flush=True)
        first = '7.2.3' if self.version.startswith('7.1.') else self.target
        target = self.prepare('target', first)
        # backup.pl creates one timestamp directory below our source directory.
        self.command(['podman', 'unshare', 'bash', '-c',
                      'mkdir -p "$2"; cp -a "$1"/*/. "$2"/', 'copy-backup',
                      str(source[0] / 'volumes/backups/source'), str(target[0] / 'volumes/backups/source')])
        hashes = self.command(['podman', 'unshare', 'sha256sum',
                               *[str(target[0] / 'volumes/backups/source' / name)
                                 for name in ['Config.tar.gz', 'Application.tar.gz', 'DatabaseBackup.sql.gz']]])
        (self.root / 'backup-sha256.txt').write_text(hashes)
        self.compose(target, 'up', '-d', 'mariadb')
        self.stage(target, 'tar -xzf "$backup/Config.tar.gz"')
        self.stage(target, 'add_config_value DatabaseHost')
        if first == '7.2.3':
            print('Offline 7.2 migration', flush=True)
            self.stage(target, 'scripts/MigrateToZnuny7_2.pl --verbose')
            env = (target[0] / '.env').read_text().replace('ZNUNY_VERSION=7.2.3', f'ZNUNY_VERSION={self.target}')
            (target[0] / '.env').write_text(env)
            (target[0] / 'override.yml').write_text(f'services:\n  znuny:\n    image: {self.target_image}\n')
        print('Offline 7.3 migration', flush=True)
        self.stage(target, 'scripts/MigrateToZnuny7_3.pl --verbose')
        self.compose(target, 'up', '-d', '--no-deps', 'znuny')
        self.ready(target, self.target)
        self.login()
        after = self.fixture(target, 'verify')
        if before != after:
            raise RuntimeError('Ticket/article/attachment identifiers or bytes changed')
        if 'Connection successful' not in self.exec(target, 'bin/znuny.Console.pl Maint::Database::Check'):
            raise RuntimeError('Database check failed')
        if 'running' not in self.exec(target, 'bin/znuny.Daemon.pl status').lower():
            raise RuntimeError('Daemon check failed')
        release = self.exec(target, 'cat RELEASE')
        if f'VERSION = {self.target}' not in release:
            raise RuntimeError('Wrong target RELEASE')
        self.exec(target, f'test "$(cat Kernel/current_version)" = {self.target}')
        result = {'source': self.version, 'target': self.target, 'target_image': self.target_image,
                  'storage': self.storage,
                  'fixture': after, 'result': 'PASS',
                  'readme_sha256': hashlib.sha256(self.readme.encode()).hexdigest()}
        (self.root / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(f'PASS {self.version} -> {self.target} ({self.storage}); login, DB, daemon, fixture preserved', flush=True)

    def cleanup(self):
        for stack in reversed(self.projects):
            try:
                self.compose(stack, 'down')
                ids = self.command(['podman', 'ps', '-aq', '--filter',
                                    f'label=com.docker.compose.project={stack[1]}']).split()
                if ids:
                    self.command(['podman', 'rm', '-f', *ids])
                self.command(['podman', 'network', 'rm', f'{stack[1]}_default'])
            except RuntimeError:
                pass


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=['7.1.3', '7.2.3'], required=True)
    parser.add_argument('--storage', choices=['ArticleStorageFS', 'ArticleStorageDB'], required=True)
    parser.add_argument('--port', type=int, default=18091)
    parser.add_argument('--target', default='7.3.7')
    parser.add_argument('--target-image')
    args = parser.parse_args()
    if not re.fullmatch(r'7\.3\.\d+', args.target):
        parser.error('Only 7.3.x targets are covered; extend intermediate stages before a new minor release')
    test = Run(args.case, args.storage, args.port, args.target,
               args.target_image or f'ghcr.io/ckbaker10/znuny:{args.target}')
    try:
        test.run()
    finally:
        test.cleanup()
