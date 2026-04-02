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

## Agent (Staff) SAML Authentication

### 1. Enable the Auth Module

In your `Kernel/Config.pm` (or a custom config file under `Kernel/Config/Files/`), add:

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
                     xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
                     xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
                     xmlns:ds="http://www.w3.org/2000/09/xmldsig#"
                     entityID="https://your-idp.example.com/auth/realms/master">
    <md:IDPSSODescriptor WantAuthnRequestsSigned="true"
                         protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
        <md:KeyDescriptor use="signing">
            <ds:KeyInfo>
                <ds:X509Data>
                    <!-- IdP signing certificate here -->
                </ds:X509Data>
            </ds:KeyInfo>
        </md:KeyDescriptor>
        <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
                                Location="https://your-idp.example.com/auth/realms/master/protocol/saml" />
    </md:IDPSSODescriptor>
</md:EntityDescriptor>';
```

> **Note:** Use either `RequestMetaDataURL` **or** `RequestMetaDataXML` — not both. The module will error and refuse to load if both or neither are set.

### 3. Required Settings

```perl
# The entity ID Znuny presents to the IdP (must match your SP registration in the IdP)
$Self->{'AuthModule::SAML::Issuer1'} = 'https://znuny.your-domain.com/';

# The URL the IdP posts the SAML response back to
# The appended query string parameters (IsSAMLLogin, Count) are added automatically
$Self->{'AuthModule::SAML::RequestAssertionConsumerURL1'} =
    'https://znuny.your-domain.com/znuny/index.pl?Action=Login';

# Text displayed on the SAML login button (translatable via AdminTranslation)
$Self->{'AuthModule::SAML::RequestLoginButtonText1'} = 'Log in via SAML';
```

### 4. Optional Settings

```perl
# Private key for signing AuthnRequests (leave unset to send requests unsigned)
$Self->{'AuthModule::SAML::RequestSignKey1'} = '/etc/znuny/saml/sp-signing.key';

# CA certificate of the IdP for certificate verification
$Self->{'AuthModule::SAML::IdPCACert1'} = '/etc/znuny/saml/idp-ca.pem';
```

---

## Agent User Sync from SAML Assertions

When enabled, Znuny can create/update agent accounts and sync group/role memberships using attributes from the SAML assertion.

### 1. Enable the Sync Module

```perl
$Self->{'AuthSyncModule1'} = 'Kernel::System::Auth::Sync::SAML';
```

### 2. Map SAML Attributes to Agent Fields

```perl
# Keys are Znuny user fields; values are SAML attribute names from the assertion
$Self->{'AuthSyncModule::SAML::UserSyncMap1'} = {
    UserFirstname => 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname',
    UserLastname  => 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname',
    UserEmail     => 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress',
};
```

> **Note:** `UserFirstname`, `UserLastname`, and `UserEmail` are required fields for `UserAdd()`. All three must be present if automatic user creation is desired.

### 3. Initial Groups for New Users

Assign newly created agents to groups automatically on their first login:

```perl
$Self->{'AuthSyncModule::SAML::UserSyncInitialGroups1'} = [
    'users',
];
```

### 4. Sync Groups from a SAML Attribute

Map SAML group membership (e.g. an `MemberOf` attribute) to Znuny groups:

```perl
# The SAML attribute that contains group names
$Self->{'AuthSyncModule::SAML::UserSyncGroupsDefinition::Attribute1'} = 'MemberOf';

# Mapping: SAML group name → Znuny group → permissions
$Self->{'AuthSyncModule::SAML::UserSyncGroupsDefinition1'} = {
    # SAML group name
    'Support' => {
        # Znuny group name => permissions hash
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
    # SAML attribute name
    'Department' => {
        # SAML attribute value => Znuny group permissions
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
    # SAML role value => Znuny role name => active (1) or inactive (0)
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

Customer portal SAML authentication uses the same underlying Request/Response modules but is configured under the `Customer::` namespace. **There is no customer-side sync module** — customers must already exist in the customer backend.

### Configuration

```perl
$Self->{'Customer::AuthModule1'} = 'Kernel::System::CustomerAuth::SAML';

# IdP metadata (same rules as agent auth — use URL or XML, not both)
$Self->{'Customer::AuthModule::SAML::RequestMetaDataURL1'} =
    'https://your-idp.example.com/auth/realms/master/protocol/saml/descriptor';

# Required
$Self->{'Customer::AuthModule::SAML::Issuer1'}                  = 'https://znuny.your-domain.com/customer/';
$Self->{'Customer::AuthModule::SAML::RequestAssertionConsumerURL1'} =
    'https://znuny.your-domain.com/znuny/customer.pl?Action=Login';
$Self->{'Customer::AuthModule::SAML::RequestLoginButtonText1'}  = 'Log in via SAML';

# Optional
$Self->{'Customer::AuthModule::SAML::RequestSignKey1'}          = '/etc/znuny/saml/sp-signing.key';
$Self->{'Customer::AuthModule::SAML::IdPCACert1'} = '/etc/znuny/saml/idp-ca.pem';
$Self->{'Customer::AuthModule::SAML::RequestMetaDataURLSSLOptions1'} = {
    SSL_ca_file     => '/your/directory/cacert.pem',
    verify_hostname => 1,
};
```

---

## Multiple Identity Providers

All configuration keys accept a numeric suffix (`1`, `2`, `3`, ..., up to `10`). To configure a second IdP:

```perl
$Self->{'AuthModule2'}                               = 'Kernel::System::Auth::SAML';
$Self->{'AuthModule::SAML::RequestMetaDataURL2'}     = 'https://second-idp.example.com/metadata';
$Self->{'AuthModule::SAML::Issuer2'}                 = 'https://znuny.your-domain.com/';
$Self->{'AuthModule::SAML::RequestAssertionConsumerURL2'} = 'https://znuny.your-domain.com/znuny/index.pl?Action=Login';
$Self->{'AuthModule::SAML::RequestLoginButtonText2'} = 'Log in via Corporate SSO';

$Self->{'AuthSyncModule2'} = 'Kernel::System::Auth::Sync::SAML';
# ... sync config with suffix 2
```

---

## How the Login Flow Works

1. Znuny renders the login page with a SAML button for each configured `AuthModule::SAML` backend.
2. Clicking the button sends the user to the IdP via an HTTP-Redirect `AuthnRequest`.
3. After successful authentication, the IdP posts a signed `SAMLResponse` back to the `RequestAssertionConsumerURL`.
4. Znuny's `Auth()` method decodes the response, validates it (issuer + request ID), and extracts the `NameID` as the login name.
5. If `AuthSyncModule::SAML` is active, user attributes, groups, and roles are synced from assertion attributes before the session is created.

---

## IdP Registration (Service Provider Metadata)

Register Znuny as a Service Provider (SP) in your IdP with:

- **Entity ID / Issuer:** the value of `AuthModule::SAML::Issuer`
- **ACS URL (POST binding):** the value of `AuthModule::SAML::RequestAssertionConsumerURL`
- **NameID format:** any format your IdP supports; the value is used as the Znuny login name
- **Signed requests:** required if `RequestSignKey` is set; provide the corresponding public certificate to the IdP

---

## Troubleshooting

| Symptom | Likely Cause |
|---|---|
| Module fails to load | Missing `Net::SAML2` CPAN module |
| "Need config AuthModule::SAML::..." error | A required config key is missing or misspelled |
| "Either give...MetaDataURL OR...MetaDataXML" | Both or neither metadata options are set |
| SAML response not valid | Issuer mismatch, clock skew, or wrong request ID (check `$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}` and IdP clock) |
| Users not created on first login | `UserSyncMap` is missing or attribute names do not match the assertion |
| Login button not appearing | Confirm the numbered config suffix is consistent across all related keys |
