# znuny-base

Base image for Znuny, built on Debian 12 (Bookworm) slim. Contains all system packages and Perl modules required to run Znuny, including modules that must be compiled from source because they are missing or too old in the Debian apt repositories.

The main [Dockerfile](Dockerfile) uses this as its base (`FROM ghcr.io/ckbaker10/znuny-base:1.0`), so the lengthy apt install and compile steps only run when dependencies actually change — not on every Znuny version build.

## Perl modules compiled from source via cpanm

These cannot be installed from apt because they are either missing or ship too old a version in Debian 12:

| Perl module | Reason |
|---|---|
| `CryptX` | Debian 12 ships too old a version (< 0.081) |
| `Crypt::JWT` | Depends on CryptX — installed alongside it |
| `Crypt::OpenSSL::RSA` | Version conflict with apt package |
| `Crypt::OpenSSL::X509` | Debian 12 ships too old a version (< 2.0.1) |
| `Net::SAML2` | Not packaged in Debian 12 — needed for SAML authentication |
| `Jq` | Not packaged in Debian 12 — needed for generic interface condition checking |

---

## Rebuilding and pushing

Only rebuild this image when you change `Dockerfile.base` (i.e. when Perl dependencies change). Bump the tag version (`1.0`, `1.1`, etc.) and update the `FROM` line in [Dockerfile](Dockerfile) to match.

### 1. Create a GitHub personal access token

GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**

Required scope: `write:packages`

### 2. Log in to the GitHub Container Registry

```bash
echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u ckbaker10 --password-stdin
```

### 3. Build the image

```bash
docker build \
  -f znuny/Dockerfile.base \
  -t ghcr.io/ckbaker10/znuny-base:1.0 \
  znuny/
```

### 4. Push the image

```bash
docker push ghcr.io/ckbaker10/znuny-base:1.0
```

### 5. Update the main Dockerfile

If you bumped the tag, update the `FROM` line in [Dockerfile](Dockerfile):

```dockerfile
FROM ghcr.io/ckbaker10/znuny-base:1.1
```

---

## Making the package public

By default ghcr.io packages are private. To allow the GitHub Actions worker to pull it without extra credentials:

GitHub → **Your profile** → **Packages** → select `znuny-base` → **Package settings** → **Change visibility** → **Public**
