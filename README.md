# Salesforce PDF Document Generation Framework

A production-ready framework for generating PDF documents from Google Docs templates using Google Apps Script middleware with **secure JWT authentication** and **direct upload** to bypass Apex heap limits.

## Architecture

```mermaid
flowchart LR
  SF[Salesforce\nFlow / Apex / Queueable] -->|1. Template ID + data| GAS[Google Apps Script\nMiddleware]
  GAS -->|2. Merge + export PDF| GAS
  GAS -->|3. JWT + REST upload| SFAPI[Salesforce REST API]
  SFAPI -->|4. ContentDocumentId| SF
```

## Features

- **Rich Template Syntax**: Merge fields, formatting, conditionals, tables, images, and more
- **Cross-Object Queries**: Query unrelated objects via `TemplateDataSource__c` (secure, admin-configured)
- **FLS Enforcement**: Automatic field-level security checking
- **Async by Default**: Queueable processing for reliability
- **Direct Upload (Required)**: GAS uploads PDFs directly to Salesforce (bypasses Apex heap limits)
- **JWT Authentication (Required)**: Secure server-to-server auth (no session IDs)

> **📖 Template Syntax**: See [TEMPLATE_SYNTAX.md](TEMPLATE_SYNTAX.md) for complete syntax reference including merge fields, formatting, conditionals, tables, images, and more.

> **IMPORTANT**: This framework requires JWT authentication to be configured. GAS uploads PDFs directly to Salesforce via REST API - there is no Base64 fallback. See Step 4 for setup.

---

## Prerequisites

Before installation, ensure you have:

- [ ] Salesforce CLI (`sf`) installed
- [ ] Access to a Salesforce org with admin permissions
- [ ] Google account with access to Google Apps Script
- [ ] `keytool` (comes with Java JDK) and `openssl` installed (for JWT setup)
- [ ] A Google Docs template to use

---

## Setup Map (Copy/Paste Targets)

This framework spans **Salesforce** and **Google Apps Script**. Use this table to avoid mixing values:

| Where | Setting | Value Source |
|------|---------|--------------|
| Salesforce → Custom Settings | `DocumentGenConfig__c.GASWebAppUrl__c` | GAS Web App URL (Step 3.4) |
| Salesforce → Custom Settings | `DocumentGenConfig__c.GASApiKey__c` | Optional API key (Step 3.3) |
| GAS → Script Properties | `SF_CONSUMER_KEY` | Connected App consumer key |
| GAS → Script Properties | `SF_USERNAME` | Salesforce service user username |
| GAS → Script Properties | `SF_LOGIN_URL` | `https://login.salesforce.com` or `https://test.salesforce.com` |
| GAS → Script Properties | `SF_PRIVATE_KEY` | PKCS#8 PEM (Step 4.2) |

---

## Installation

### Step 1: Deploy Salesforce Metadata

```bash
# Clone or download the repository
cd googlePdf

# Deploy to your Salesforce org
sf project deploy start --source-dir force-app
```

### Step 1b: Assign Permission Set + Tabs

1. Go to **Setup > Permission Sets**
2. Assign **Document Generation Service User** to the user that will run the integration (or your admin user)
3. Optional: Add the custom tabs to your app navigation:
   - **Document Templates**
   - **Document Generation Logs**

### Step 2: Configure Salesforce Custom Setting

#### 2.1 Create DocumentGenConfig__c Custom Setting

1. Go to **Setup > Custom Settings > Document Generation Config > Manage**
2. Click **New** and create a record:

| Field | Value |
|-------|-------|
| GAS Web App URL | *(leave blank for now, fill after Step 3)* |
| GAS API Key | `your-secret-key-123` *(optional but recommended)* |
| Enable Logging | ✅ Checked |
| Max Docs Per Batch | `10` |
| GAS Timeout Ms | `120000` |

#### 2.2 Create Remote Site Settings (only if not using Named Credential)

1. Go to **Setup > Remote Site Settings**
2. Add these if they don't exist:

| Name | URL |
|------|-----|
| GoogleAppsScript | `https://script.google.com` |
| GoogleUserContent | `https://script.googleusercontent.com` |

#### 2.3 (Recommended) Create Named Credential for GAS Endpoint

This avoids Remote Site Settings and is preferred by `GASDocumentService`.

1. Go to **Setup > Named Credentials** → **New**
2. Name: `GAS_Document_Generator`
3. URL: *(your GAS Web App URL from Step 3.4)*
4. Authentication: **Anonymous**
5. **Generate Authorization Header**: Disabled

---

### Step 3: Deploy Google Apps Script

#### 3.1 Create GAS Project

1. Go to [Google Apps Script](https://script.google.com)
2. Click **New project**
3. Rename the project to "Salesforce Document Generator"

#### 3.2 Copy GAS Files

Copy all files from `gas-middleware/` folder to your GAS project:

| File | Purpose |
|------|---------|
| `Code.gs` | Main entry point, handles requests |
| `DocumentService.gs` | Google Drive/Docs operations, Salesforce upload |
| `TemplateProcessor.gs` | Field replacement logic |
| `ConditionalProcessor.gs` | IF/ELSE logic and conditional evaluation |
| `ExpressionEvaluator.gs` | Expression parsing for conditionals |
| `TableHandler.gs` | Table/repeater processing |
| `DocumentCache.gs` | Performance: Text caching to reduce API calls |
| `FormatUtils.gs` | Value formatting (currency, date, etc.) |
| `ImageHandler.gs` | Image embedding from URLs (with caching) |
| `SalesforceAuth.gs` | JWT authentication for direct upload |
| `appsscript.json` | GAS configuration (includes Docs API) |

#### 3.2b Enable Google Docs Advanced Service

**Required for Batch API performance optimization:**

1. In the GAS editor, click **Services** (+) in the left sidebar
2. Search for **"Google Docs API"**
3. Select **v1** and click **Add**
4. You should see "Docs" listed under Services

> **Note**: The `appsscript.json` already includes the configuration, but you must manually enable the service in the editor.

#### 3.3 Configure API Key (Optional but Recommended)

In `Code.gs`, set the API key to match your Salesforce config:

```javascript
const CONFIG = {
  VERSION: '1.0',
  API_KEY: 'your-secret-key-123',  // Must match DocumentGenConfig__c.GASApiKey__c
  // ...
};
```

#### 3.4 Deploy as Web App

1. Click **Deploy > New deployment**
2. Click the gear icon ⚙️ and select **Web app**
3. Configure:
   - **Description**: `v1.0`
   - **Execute as**: `Me`
   - **Who has access**: `Anyone`
4. Click **Deploy**
5. **Copy the Web App URL** (you'll need this for Salesforce config)

#### 3.5 Update Salesforce Config

Go back to **Setup > Custom Settings > Document Generation Config > Manage** and update:
- **GAS Web App URL**: Paste the Web App URL from Step 3.4

---

### Step 4: Setup JWT Authentication (Direct Upload)

This enables GAS to upload PDFs directly to Salesforce, bypassing Apex heap limits.

#### 4.1 Create Connected App + Service User in Salesforce

Create a **Connected App** (JWT OAuth) and a **service user** with API access. You will need:
- Connected App **Consumer Key**
- Service user **username**

**Connected App + Auth Setup (same steps as the setup script):**
1. **Create a JWT signing certificate**
   - Setup → **Certificate and Key Management** → **Create Self-Signed Certificate**
   - Label: `Document Generation JWT Signer`
   - API Name: `DocGenJWTSigner`
   - Key Size: **2048**
   - Exportable Private Key: **Enabled**
2. **Create Connected App**
   - Setup → **App Manager** → **New Connected App**
   - Label: `Document Generation GAS Integration`
   - API Name: `DocGenGASIntegration`
   - Contact Email: your admin email
   - Enable **OAuth Settings**
   - Callback URL: `https://login.salesforce.com/services/oauth2/callback`
   - **Use digital signatures** → select `DocGenJWTSigner`
   - OAuth scopes:
     - `Access and manage your data (api)`
     - `Perform requests on your behalf at any time (refresh_token, offline_access)`
   - Save, then **Manage Consumer Details** → copy **Consumer Key**
3. **Create External Credential (JWT Bearer)**
   - Setup → **Named Credentials** → **External Credentials** → **New**
   - Label: `Document Generation Service User`
   - API Name: `DocGenServiceUser`
   - Authentication Protocol: **OAuth 2.0**
   - Authentication Flow Type: **JWT Bearer**
   - **Principal**: add a **Named Principal** called `DocGenServicePrincipal`
   - **Parameters**:
    - Auth Provider URL: `https://<your-org-domain>.my.salesforce.com/services/oauth2/token` (or sandbox domain)
     - Signing Certificate: `DocGenJWTSigner`
     - JWT Claims:
       - `iss` = Consumer Key
       - `sub` = service user username
       - `aud` = `"https://login.salesforce.com"` (or `"https://test.salesforce.com"`)
4. **Create Named Credential (points to your org)**
   - Setup → **Named Credentials** → **New**
   - Label: `Document Generation Salesforce API`
   - API Name: `DocGenSalesforceAPI`
   - URL: `https://<your-org-domain>.my.salesforce.com` (or `https://<your-org-domain>.sandbox.my.salesforce.com`)
   - Authentication: **External Credential** → select `DocGenServiceUser` / `DocGenServicePrincipal`
   - **Generate Authorization Header**: Enabled
5. **Assign permission set to the service user**
   - Assign **Document Generation Service User** to the JWT service user

> **Note**: Steps 3–4 (External Credential + Named Credential) mirror the setup script output. The core GAS → Salesforce upload uses JWT directly from GAS; these credentials are only needed if you plan to use Salesforce-side callouts to Salesforce APIs.

#### 4.2 Export the Private Key

The setup created a certificate. Now extract the private key:

**In Salesforce:**
1. Go to **Setup > Certificate and Key Management**
2. Find **"Document Generation JWT Signer"** (or `DocGenJWTSigner`)
3. Click **Export to Keystore**
4. Enter a password (remember it!) and download the `.jks` file

**In Terminal:**
```bash
cd /path/to/downloaded/file

# Run the extraction script (included in this repo)
./scripts/extract_private_key.sh DocGenJWTSigner.jks docgenjwtsigner

# Or manually:
# 1. Convert JKS to PKCS12
keytool -importkeystore \
  -srckeystore DocGenJWTSigner.jks \
  -destkeystore temp.p12 \
  -deststoretype PKCS12 \
  -srcalias docgenjwtsigner

# 2. Extract private key
openssl pkcs12 -in temp.p12 -nocerts -nodes -out private_key.pem

# 3. View the key
cat private_key.pem
```

> **Key format requirement**: GAS expects **PKCS#8 PEM** with `-----BEGIN PRIVATE KEY-----` header. If you see `-----BEGIN CERTIFICATE-----`, it's the wrong file.

#### 4.3 Configure GAS Script Properties

1. In your GAS project, go to **Project Settings** (gear icon ⚙️)
2. Scroll to **Script Properties**
3. Click **Add Script Property** and add these 4 properties:

| Property | Value |
|----------|-------|
| `SF_CONSUMER_KEY` | Connected App consumer key |
| `SF_USERNAME` | Service user username |
| `SF_LOGIN_URL` | `https://login.salesforce.com` (or `https://test.salesforce.com` for sandbox) |
| `SF_PRIVATE_KEY` | **Entire contents** of `private_key.pem` including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` |

#### 4.4 Test JWT Authentication

In GAS Script Editor, run:

```javascript
function testSalesforceAuth() {
  console.log('Testing Salesforce JWT Authentication...');
  const result = SalesforceAuth.testAuth();
  console.log('Config Valid: ' + result.configValid);
  console.log('Token Obtained: ' + result.tokenObtained);
  console.log('Instance URL: ' + result.instanceUrl);
  if (result.success) {
    console.log('✓ Authentication successful!');
  } else {
    console.log('✗ Authentication failed: ' + result.error);
  }
}
```

Click **Run** and check the **Execution log**. You should see:
```
Config Valid: true
Token Obtained: true
Instance URL: https://your-org.my.salesforce.com
✓ Authentication successful!
```

#### 4.5 Redeploy GAS (Important!)

After adding Script Properties, create a new deployment version:

1. Click **Deploy > Manage deployments**
2. Click the **pencil icon** (edit)
3. Change **Version** to **"New version"**
4. Click **Deploy**

---

### Step 5: Create a Template

#### 5.1 Create Google Doc Template

1. Create a new Google Doc
2. Add merge fields using `{{FieldName}}` syntax
3. Copy the **Document ID** from the URL:
   ```
   https://docs.google.com/document/d/1ABC123xyz.../edit
                                      └─────────┘
                                      This is the ID
   ```

Example template content:
```
INVOICE

Invoice #: {{InvoiceNumber__c}}
Date: {{InvoiceDate__c:date}}
Due: {{DueDate__c:date}}

Bill To:
{{Account.Name}}
{{Account.BillingStreet}}
{{Account.BillingCity}}, {{Account.BillingState}} {{Account.BillingPostalCode}}

{{#OpportunityLineItems}}
| {{Product2.Name}} | {{Quantity}} | {{UnitPrice:currency}} | {{TotalPrice:currency}} |
{{/OpportunityLineItems}}

Subtotal: {{SubTotal__c:currency}}
Tax: {{TaxAmount__c:currency}}
Total: {{GrandTotal__c:currency}}
```

> **📖 Template Syntax**: For complete syntax reference including conditionals, formatting options, images, and advanced features, see [TEMPLATE_SYNTAX.md](TEMPLATE_SYNTAX.md).

#### 5.2 Create DocumentTemplate__c Record

In Salesforce, create a new `DocumentTemplate__c` record:

| Field | Value |
|-------|-------|
| Name | `InvoiceTemplate` |
| Object API Name | `Opportunity` |
| Google Doc ID | *(the ID from step 5.1)* |
| Output File Name | `Invoice_{{InvoiceNumber__c}}` |
| Is Active | ✅ Checked |

#### 5.3 Validate the Template

Run in Anonymous Apex:
```apex
Id templateId = [SELECT Id FROM DocumentTemplate__c WHERE Name = 'InvoiceTemplate' LIMIT 1].Id;
TemplateValidationService.ValidationResult result = TemplateValidationService.validateTemplate(templateId);
System.debug('Valid: ' + result.isValid);
System.debug('Fields: ' + result.parsedFields);
if (!result.warnings.isEmpty()) {
    System.debug('Warnings: ' + result.warnings);
}
```

---

### Step 6: Test Document Generation

#### Option A: Quick Test (Async)

```apex
// Get an Opportunity ID
Id oppId = [SELECT Id FROM Opportunity LIMIT 1].Id;

// Generate document (async by default)
DocumentGeneratorAction.DocumentGeneratorOutput result =
    DocumentGeneratorAction.generateDocument(oppId, 'InvoiceTemplate');

System.debug('Async Job ID: ' + result.asyncJobId);
// Check Apex Jobs or DocumentGenerationLog__c for results
```

#### Option B: Use Test Script

Edit `scripts/TestDocumentGeneration.apex`:
```apex
String RECORD_ID = '006...';  // Your Opportunity ID
String TEMPLATE_NAME = 'InvoiceTemplate';
```

Then run the script in Developer Console. Check Apex Jobs for status.

---

## Usage

### From Flow

1. Add the **"Generate PDF Document"** action
2. Configure inputs:
   - **Record ID**: `{!recordId}`
   - **Template Developer Name**: `InvoiceTemplate`
   - **Attach to Record**: `true`
3. The output `asyncJobId` contains the Queueable job ID
4. Check `DocumentGenerationLog__c` for results

> **Note**: All generation is asynchronous. The PDF will be attached to the record once the job completes.

### From Apex

```apex
// Single record
DocumentGeneratorAction.generateDocument(recordId, 'TemplateName');

// Multiple records (batched via Queueable)
Id jobId = DocumentGeneratorAction.generateDocumentsAsync(recordIds, 'TemplateName');

// Full control via Input class
DocumentGeneratorAction.DocumentGeneratorInput input = new DocumentGeneratorAction.DocumentGeneratorInput();
input.recordId = recordId;
input.templateDeveloperName = 'TemplateName';
input.outputFileName = 'Custom_Invoice_{{Name}}';
DocumentGeneratorAction.generateDocuments(new List<DocumentGeneratorAction.DocumentGeneratorInput>{ input });
```

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "GAS did not return ContentDocumentId" | JWT auth not configured - complete Step 4 |
| "Salesforce JWT authentication not configured" | Set Script Properties in GAS - see Step 4.3 |
| JWT "Invalid argument: key" | Private key format wrong - see Step 4.2 |
| "GAS Web App URL not configured" | Add URL to `DocumentGenConfig__c` Custom Setting |
| "Template not found" | Check template `Name` and `IsActive__c = true` |
| GAS returns HTML instead of JSON | Redeploy GAS as new version |

> **Note**: JWT authentication is REQUIRED. There is no Base64 fallback. Run `testSalesforceAuth()` in GAS to verify configuration.

### Debug Commands

**Check generation logs:**
```apex
List<DocumentGenerationLog__c> logs = [
    SELECT Status__c, ErrorMessage__c, DurationMs__c, CreatedDate
    FROM DocumentGenerationLog__c
    ORDER BY CreatedDate DESC
    LIMIT 10
];
System.debug(logs);
```

### GAS Debugging

1. In GAS project, click **Executions** (left menu)
2. View logs for each request
3. Run `debugPrivateKey()` to diagnose JWT issues

---

## Security

### JWT Bearer Authentication
- No Salesforce session IDs are transmitted to GAS
- GAS authenticates using RSA-signed JWT tokens
- Access tokens are short-lived (~15 minutes)
- All API access is audited via Connected App logs

### API Key Protection
- Optional API key validates requests from Salesforce
- Prevents unauthorized access to GAS endpoint
- Set in both GAS `Code.gs` and Salesforce `DocumentGenConfig__c` Custom Setting

### FLS Enforcement
- All queries use `WITH USER_MODE`
- Field-level security is automatically enforced
- Users only see data they have access to

---

## License

MIT License - See LICENSE file for details.
