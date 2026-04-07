# Znuny 7.3.1 — SAML 2.0 Authentication Setup Guide

This guide documents the SAML 2.0 authentication feature introduced in Znuny **7.3.1** (relative to 7.2.3).

---

## Overview of Changes (7.2.3 → 7.3.1)

The following new modules were added:

| File | Purpose |
|---|---|
| `Kernel/System/Auth/SAML.pm` | Agent authentication via SAML 2.0 |
| `Kernel/System/Auth/SAML/Request.pm` | Builds and signs SAML `AuthnRequest` |
| `Kernel/System/Auth/SAML/Response.pm` | Decodes and validates SAML `Response` |
| `Kernel/System/Auth/Sync/SAML.pm` | Syncs agent user attributes/groups/roles from SAML assertions |
| `Kernel/System/CustomerAuth/SAML.pm` | Customer user authentication via SAML 2.0 |

Login templates (`Login.tt`, `CustomerLogin.tt`) were updated to render an optional SAML login button block (`SAMLLoginLink`).

The `Kernel/Config/Defaults.pm` was extended with commented-out example configuration for both agent and customer SAML auth.

---

## Prerequisites

### Perl Dependency

SAML support requires the `Net::SAML2` CPAN module, which is **not** available as a standard Debian/Ubuntu package:

```bash
cpanm --notest Net::SAML2
```

Also ensure the following are available (typically already present):

- `MIME::Base64`
- `XML::LibXML`
- `XML::LibXML::XPathContext`

---

## SP Signing Key

Znuny acts as a SAML Service Provider (SP). If your IdP requires signed `AuthnRequest` messages
(`WantAuthnRequestsSigned="true"` in the IdP metadata), you must generate an RSA keypair for Znuny.

### Generate the keypair

```bash
# Run on the Docker host — output goes into the persistent config volume
openssl genrsa -out volumes/config/sp.key 2048
openssl req -new -key volumes/config/sp.key \
  -x509 -days 3650 \
  -subj "/CN=znuny-sp" \
  -out volumes/config/sp.crt
```

The key will be available inside the container at `/opt/znuny/Kernel/sp.key`.

> **Critical — key format:** `Net::SAML2` requires the private key in **PKCS#1 format**
> (`-----BEGIN RSA PRIVATE KEY-----`). If you use a key in PKCS#8 format
> (`-----BEGIN PRIVATE KEY-----`), the module will fail at runtime with:
>
> ```
> FATAL: rsa_sign_hash_ex failed: A private PK key is required.
> ```
>
> The `openssl genrsa` command above always produces PKCS#1. If you have an existing PKCS#8 key,
> convert it:
>
> ```bash
> openssl rsa -in sp.key -out sp.key.pkcs1 && mv sp.key.pkcs1 sp.key
> ```

### Register the SP certificate with the IdP

Upload `sp.crt` to your IdP so it can verify signed `AuthnRequest` messages:

- **Keycloak:** Clients → `<your-client>` → Keys → Import Certificate → paste contents of `sp.crt`

---

## Agent (Staff) SAML Authentication

### 1. Enable the Auth Module

In `volumes/config/Config.pm`:

```perl
# Use index 1 (or 2, 3, ... for multiple IdPs)
$Self->{'AuthModule1'} = 'Kernel::System::Auth::SAML';
```

### 2. Configure the Identity Provider (IdP) Metadata

**Option A — Fetch metadata from a URL:**

```perl
$Self->{'AuthModule::SAML::RequestMetaDataURL1'} = 'https://your-idp.example.com/auth/realms/master/protocol/saml/descriptor';

# Optional SSL options when using a metadata URL
$Self->{'AuthModule::SAML::RequestMetaDataURLSSLOptions1'} = {
    SSL_ca_file     => '/your/directory/cacert.pem',
    SSL_ca_path     => '/etc/ssl/certs',
    verify_hostname => 1,
};
```

**Option B — Embed metadata as an XML string:**

```perl
$Self->{'AuthModule::SAML::RequestMetaDataXML1'} = '<?xml version="1.0" encoding="UTF-8" ?>
<md:EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata"
                     ...>
    ...
</md:EntityDescriptor>';
```

> **Note:** Use either `RequestMetaDataURL` **or** `RequestMetaDataXML` — not both.
> The module will log an error and refuse to initialise if both or neither are set.

### 3. Required Settings

```perl
# The entity ID Znuny presents to the IdP (must match the Client ID / SP registration in the IdP).
# Must use HTTPS if Znuny is served over HTTPS — the IdP checks this.
$Self->{'AuthModule::SAML::Issuer1'} = 'https://znuny.your-domain.com/znuny/';

# The URL the IdP posts the SAML response back to after successful login.
# Must also use HTTPS if the site is HTTPS — a mismatch causes a redirect loop or IdP rejection.
$Self->{'AuthModule::SAML::RequestAssertionConsumerURL1'} =
    'https://znuny.your-domain.com/znuny/index.pl?Action=Login';

# Text displayed on the SAML login button
$Self->{'AuthModule::SAML::RequestLoginButtonText1'} = 'Log in via SSO';
```

> **http vs https pitfall:** If Znuny is served over HTTPS but `Issuer` or
> `RequestAssertionConsumerURL` use `http://`, the `AuthnRequest` will send the wrong URLs.
> The IdP will either reject the request (unknown client) or post the response to an http URL
> which your reverse proxy may not accept. Always use the same scheme as the browser-facing URL.

### 4. Optional Settings

```perl
# Private key for signing AuthnRequests (PKCS#1 format — see key generation section above).
# Required when IdP metadata declares WantAuthnRequestsSigned="true".
$Self->{'AuthModule::SAML::RequestSignKey1'} = '/opt/znuny/Kernel/sp.key';

# CA certificate of the IdP for certificate verification
$Self->{'AuthModule::SAML::IdPCACert1'} = '/etc/znuny/saml/idp-ca.pem';
```

---

## Agent User Sync from SAML Assertions

When enabled, Znuny can create/update agent accounts and sync group/role memberships using
attributes from the SAML assertion. Without this module, authentication may succeed but the user
will see: *"Authentication succeeded, but no user data record is found in the database."*

### 1. Enable the Sync Module

```perl
$Self->{'AuthSyncModule1'} = 'Kernel::System::Auth::Sync::SAML';
```

### 2. Map SAML Attributes to Agent Fields

```perl
# Keys are Znuny user fields; values are SAML attribute names from the assertion.
# UserFirstname, UserLastname, and UserEmail are all required for UserAdd() to succeed.
# If any of these are missing or empty in the SAML response, user creation will silently
# fail and the login will be rejected with "username and password entered incorrectly".
$Self->{'AuthSyncModule::SAML::UserSyncMap1'} = {
    UserFirstname => 'firstName',
    UserLastname  => 'lastName',
    UserEmail     => 'email',
};
```

> **Attribute name pitfall:** The attribute names in `UserSyncMap` must exactly match the
> `Name=` attribute of `<saml:Attribute>` elements in the SAMLResponse. Decode a response
> to check what your IdP actually sends:
>
> ```bash
> # Capture the SAMLResponse POST body, then:
> echo "<base64_value>" | base64 -d | grep -o 'Name="[^"]*"'
> ```
>
> Common Keycloak attribute names: `firstName`, `lastName`, `email`
> Common Active Directory / WS-Fed names via Keycloak:
> - `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname`
> - `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname`
> - `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress`
>
> If the IdP sends a `displayName` (full name) but no split first/last name, you can map
> the same attribute to both fields as a workaround:
>
> ```perl
> $Self->{'AuthSyncModule::SAML::UserSyncMap1'} = {
>     UserFirstname => 'displayName',
>     UserLastname  => 'displayName',
>     UserEmail     => 'userPrincipalName',  # or whichever attribute holds the email
> };
> ```
>
> The correct long-term fix is to add proper attribute mappers in the IdP.

> **Empty attribute pitfall:** Some IdPs include attribute elements in every response but leave
> them with empty values. An empty attribute value is treated as missing by the sync module —
> the same result as the attribute not being configured. Verify attribute values are actually
> populated, not just present.

### 3. Initial Groups for New Users

Assign newly created agents to groups automatically on their first login.
The `users` group is required for agents to be able to access any queue.

```perl
$Self->{'AuthSyncModule::SAML::UserSyncInitialGroups1'} = [
    'users',
];
```

> **Group must exist:** If a group listed here does not exist in Znuny, the sync module logs
> a notice and skips it. The user is still created, but without group membership — which means
> they will not see any queues after login.

### 4. Sync Groups from a SAML Attribute

Map SAML group membership (e.g. an `MemberOf` attribute) to Znuny groups:

```perl
# The SAML attribute that contains group names
$Self->{'AuthSyncModule::SAML::UserSyncGroupsDefinition::Attribute1'} = 'MemberOf';

# Mapping: SAML group name → Znuny group → permissions
$Self->{'AuthSyncModule::SAML::UserSyncGroupsDefinition1'} = {
    'Support' => {
        'ZnunyGroup1' => { rw => 1 },
        'ZnunyGroup2' => { ro => 1, note => 1 },
    },
    'Operations' => {
        'ZnunyGroup3' => { rw => 1 },
    },
};
```

### 5. Sync Groups from Arbitrary SAML Attribute Values

```perl
$Self->{'AuthSyncModule::SAML::UserSyncAttributeGroupsDefinition1'} = {
    'Department' => {
        'IT' => {
            admin => { rw => 1, ro => 1 },
            faq   => { rw => 0, ro => 1 },
        },
        'Sales' => {
            users => { rw => 1, ro => 1 },
        },
    },
};
```

### 6. Sync Roles from a SAML Attribute

```perl
$Self->{'AuthSyncModule::SAML::UserSyncRolesDefinition::Attribute1'} = 'Role';

$Self->{'AuthSyncModule::SAML::UserSyncRolesDefinition1'} = {
    'Operations' => {
        ZnunyRole1 => 1,
        ZnunyRole2 => 0,
    },
};
```

### 7. Sync Roles from Arbitrary SAML Attribute Values

```perl
$Self->{'AuthSyncModule::SAML::UserSyncAttributeRolesDefinition1'} = {
    'Department' => {
        'IT' => {
            Role1 => 1,
            Role2 => 0,
        },
    },
};
```

---

## Customer User SAML Authentication

Customer portal SAML authentication uses the same underlying Request/Response modules but is
configured under the `Customer::` namespace. **There is no customer-side sync module** — customers
must already exist in the customer backend.

### Configuration

```perl
$Self->{'Customer::AuthModule1'} = 'Kernel::System::CustomerAuth::SAML';

# IdP metadata (same rules as agent auth — use URL or XML, not both)
$Self->{'Customer::AuthModule::SAML::RequestMetaDataURL1'} =
    'https://your-idp.example.com/auth/realms/master/protocol/saml/descriptor';

# Required
$Self->{'Customer::AuthModule::SAML::Issuer1'}                       = 'https://znuny.your-domain.com/customer/';
$Self->{'Customer::AuthModule::SAML::RequestAssertionConsumerURL1'}  =
    'https://znuny.your-domain.com/znuny/customer.pl?Action=Login';
$Self->{'Customer::AuthModule::SAML::RequestLoginButtonText1'}       = 'Log in via SSO';

# Optional
$Self->{'Customer::AuthModule::SAML::RequestSignKey1'}               = '/opt/znuny/Kernel/sp.key';
$Self->{'Customer::AuthModule::SAML::IdPCACert1'}                    = '/etc/znuny/saml/idp-ca.pem';
```

---

## Multiple Identity Providers

All configuration keys accept a numeric suffix (`1`, `2`, `3`, ..., up to `10`). To configure a second IdP:

```perl
$Self->{'AuthModule2'}                                    = 'Kernel::System::Auth::SAML';
$Self->{'AuthModule::SAML::RequestMetaDataURL2'}          = 'https://second-idp.example.com/metadata';
$Self->{'AuthModule::SAML::Issuer2'}                      = 'https://znuny.your-domain.com/znuny/';
$Self->{'AuthModule::SAML::RequestAssertionConsumerURL2'} = 'https://znuny.your-domain.com/znuny/index.pl?Action=Login';
$Self->{'AuthModule::SAML::RequestLoginButtonText2'}      = 'Log in via Corporate SSO';

$Self->{'AuthSyncModule2'} = 'Kernel::System::Auth::Sync::SAML';
# ... sync config with suffix 2
```

---

## How the Login Flow Works

1. Znuny renders the login page with a SAML button for each configured `AuthModule::SAML` backend.
2. Clicking the button sends the user to the IdP via an HTTP-Redirect `AuthnRequest`.
3. After successful authentication, the IdP POSTs a signed `SAMLResponse` to the `RequestAssertionConsumerURL`.
4. Znuny's `Auth()` decodes the response, validates it (issuer + request ID), and extracts the `NameID` as the login name.
5. If `AuthSyncModule::SAML` is active, the user is created/updated and group/role memberships are synced before the session is established.

---

## IdP Registration (Service Provider Metadata)

When registering Znuny as an SP in your IdP, use these values:

### Client ID / Entity ID
The value of `AuthModule::SAML::Issuer` — must include the trailing slash:
```
https://<your-server>/znuny/
```

### ACS URL (Assertion Consumer Service URL)
The value of `AuthModule::SAML::RequestAssertionConsumerURL`:
```
https://<your-server>/znuny/index.pl?Action=Login
```
Binding: **HTTP-POST**. The `AuthnRequest` uses HTTP-Redirect; the response always comes back as a POST.

### NameID Format
Any format your IdP supports. The NameID value becomes the agent's `UserLogin` in Znuny.
Ensure it is stable (does not change when the user's name changes) and unique.

### Signed Requests
Required when `RequestSignKey` is configured. Upload the corresponding `sp.crt` to the IdP.

---

## Keycloak-Specific Notes

### Required Attribute Mappers

By default, Keycloak does not include user attributes in SAML assertions unless mappers are
explicitly configured. Without mappers, all `<saml:AttributeValue>` elements will be present
but **empty**, causing user sync to fail silently.

Add mappers under: **Clients → `<client-id>` → Client scopes → `<client>-dedicated` → Add mapper**

| Mapper type | User property/attribute | SAML attribute name |
|---|---|---|
| User Property | `firstName` | `firstName` |
| User Property | `lastName` | `lastName` |
| User Property | `email` | `email` |

### WantAuthnRequestsSigned

If the IdP metadata includes `WantAuthnRequestsSigned="true"`, you **must** set `RequestSignKey`.
Omitting it causes a `FATAL: rsa_sign_hash_ex failed: A private PK key is required` error on
every login attempt and a 500 response to the user.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| 500 error on every page load | `Net::SAML2` XS module fails to load | Rebuild image with `--no-cache`; verify with `docker compose exec znuny perl -MNet::SAML2 -e 'print "OK\n"'` |
| `rsa_sign_hash_ex failed: A private PK key is required` | `sp.key` is in PKCS#8 format or missing | Regenerate with `openssl genrsa`; check with `head -1 sp.key` |
| SAML button missing on login page | Config key suffix mismatch or config not loaded | Check all related keys use the same numeric suffix; restart container |
| Issuer or ACS URL sent as `http://` instead of `https://` | `Issuer` / `RequestAssertionConsumerURL` use wrong scheme | Change both to `https://` in Config.pm |
| "Need config AuthModule::SAML::..." error | Required config key missing or misspelled | Check key names — no extra `::` separators |
| "Either give...MetaDataURL OR...MetaDataXML" | Both or neither metadata options are set | Use exactly one of the two |
| "Authentication succeeded, but no user data record is found" | `AuthSyncModule1` not configured | Add `AuthSyncModule1 = Kernel::System::Auth::Sync::SAML` and `UserSyncMap1` |
| "username and password entered incorrectly" after SAML success | `UserSyncMap` attribute names don't match assertion, or attribute values are empty | Decode the SAMLResponse and compare `Name=` values; verify attributes have non-empty values in the IdP |
| `Need UserID!` in logs from `Sync::SAML::Sync` | User creation failed because `%SyncUser` was empty | Fix `UserSyncMap` attribute names to match the actual assertion |
| Users created with login but wrong name/email | `UserSyncMap` maps to wrong or fallback attributes | Update map to correct attribute names once IdP mappers are configured |
| Apache crash loop: `Address already in use` | Apache killed with SIGKILL, socket not released before respawn | Restart the container: `docker compose restart znuny` |
