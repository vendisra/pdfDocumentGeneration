/**
 * TestDocumentGeneration - Full integration test using real document processing
 *
 * HOW TO USE:
 * 1. Copy this file to Google Apps Script
 * 2. Run: testFullDocumentGeneration()
 * 3. View execution logs to see what's happening
 *
 * This test:
 * - Uses your REAL template document
 * - Uses the REAL JSON data from log.txt
 * - Calls the ACTUAL processing functions (TableHandler, TemplateProcessor)
 * - Shows detailed logs at each step
 */

/**
 * Main test - processes your actual invoice template with real data
 *
 * IMPORTANT: Replace TEMPLATE_DOC_ID with your template document ID
 */
function testFullDocumentGeneration() {
  Logger.log('========================================');
  Logger.log('FULL DOCUMENT GENERATION TEST');
  Logger.log('========================================\n');

  // YOUR TEMPLATE DOCUMENT ID (from log.txt)
  const TEMPLATE_DOC_ID = '1180oU1mLF_DM5IMBcB3UpumRw35kIoIQSm1LjtL05Ks';

  Logger.log('Step 1: Loading template document...');
  Logger.log('Template ID: ' + TEMPLATE_DOC_ID);

  // Make a copy to test with (so we don't modify the original)
  const originalFile = DriveApp.getFileById(TEMPLATE_DOC_ID);
  const testFile = originalFile.makeCopy('TEST - Invoice Generation - ' + new Date().getTime());
  const testDocId = testFile.getId();

  Logger.log('Created test copy: ' + testDocId);
  Logger.log('URL: https://docs.google.com/document/d/' + testDocId + '/edit');
  Logger.log('');

  // Real data from log.txt (complete structure)
  const recordData = {
    // Field type metadata for auto-formatting
    _fieldTypes: {
      "OpportunityLineItems.TotalPrice": "CURRENCY",
      "OpportunityLineItems.UnitPrice": "CURRENCY",
      "OpportunityLineItems.Quantity": "NUMBER",
      "CompanyLogoUrl__c": "URL",
      "IsWon": "BOOLEAN",
      "GrandTotal__c": "CURRENCY",
      "DiscountAmount__c": "CURRENCY",
      "DiscountPercent__c": "PERCENT",
      "TaxAmount__c": "CURRENCY",
      "TaxRate__c": "PERCENT",
      "SubTotal__c": "CURRENCY",
      "DueDate__c": "DATE",
      "InvoiceDate__c": "DATE"
    },

    // System variables (includes ORG with null Phone)
    TODAY: "2026-01-25",
    NOW: "2026-01-25, 4:40 a.m.",
    RECORD_ID: "006DS00000NY3S9YAL",
    CURRENT_USER: {
      Id: "005DS00000yHyrwYAC",
      Name: "User User",
      FirstName: "User",
      LastName: "User",
      Email: "iamsonal@gmail.com"
    },
    ORG: {
      Name: "aiAgentStudio - Dev Org",
      Street: null,
      City: null,
      State: null,
      PostalCode: null,
      Phone: null,  // THIS IS NULL - will cause error without default value!
      Country: "CA"
    },

    // Main opportunity fields
    Id: "006DS00000NY3S9YAL",
    AccountId: "001DS00001XOL4KYAX",
    InvoiceNumber__c: "INV-2024-0001",
    InvoiceDate__c: "2026-01-23",
    DueDate__c: "2026-02-22",
    PaymentTerms__c: "Net 30",
    PaymentMethod__c: "Wire Transfer",
    SubTotal__c: 90000.00,
    TaxRate__c: 8.50,
    TaxAmount__c: 7650.00,
    DiscountPercent__c: 5.00,
    DiscountAmount__c: 4500.00,
    GrandTotal__c: 93150.00,
    BankName__c: "First National Bank",
    BankAccountNumber__c: "****1234",
    BankRoutingNumber__c: "123456789",
    BankSwiftCode__c: "FNBAUS33XXX",
    BillingNotes__c: "Early payment discount available: 2% if paid within 10 days.",
    IsWon: true,
    CompanyLogoUrl__c: "https://placehold.co/200x80/0066FF/FFFFFF/png",

    // Account relationship with parent hierarchy
    Account: {
      Id: "001DS00001XOL4KYAX",
      Name: "INV Enterprise Solutions",
      BillingStreet: "123 Innovation Drive, Building A",
      BillingCity: "Austin",
      BillingState: "TX",
      BillingPostalCode: "78701",
      Phone: "(555) 200-1234",
      Website: "www.enterprise.example.com",
      Industry: "Manufacturing",
      ParentId: "001DS00001XOL4JYAX",
      OwnerId: "005DS00000yHyrwYAC",
      Owner: {
        Id: "005DS00000yHyrwYAC",
        Name: "User User"
      },
      Parent: {
        Id: "001DS00001XOL4JYAX",
        Name: "INV North America Inc",
        ParentId: "001DS00001XOKl3YAH",
        Parent: {
          Id: "001DS00001XOKl3YAH",
          Name: "INV Global Holdings"
        }
      }
    },

    // Data source for OpenCases
    OpenCases: [
      {
        Id: "500DS00000GsoAdYAJ",
        CaseNumber: "00001249",
        Subject: "Integration requirements discussion",
        Status: "Working",
        Priority: "Medium",
        CreatedDate: "2026-01-23T21:48:03.000Z",
        LastModifiedDate: "2026-01-23T21:48:03.000Z"
      },
      {
        Id: "500DS00000GsoAeYAJ",
        CaseNumber: "00001250",
        Subject: "Data migration planning",
        Status: "New",
        Priority: "High",
        CreatedDate: "2026-01-23T21:48:03.000Z",
        LastModifiedDate: "2026-01-23T21:48:03.000Z"
      },
      {
        Id: "500DS00000GsoAfYAJ",
        CaseNumber: "00001251",
        Subject: "Training schedule coordination",
        Status: "New",
        Priority: "Low",
        CreatedDate: "2026-01-23T21:48:03.000Z",
        LastModifiedDate: "2026-01-23T21:48:03.000Z"
      }
    ]
  };

  const childData = {
    OpportunityLineItems: [
      {
        Id: "00kDS00000A3iDnYAJ",
        OpportunityId: "006DS00000NY3S9YAL",
        Product2Id: "01tDS00000JxckgYAB",
        Product2: {
          Id: "01tDS00000JxckgYAB",
          Name: "Enterprise Platform License",
          ImageUrl__c: "https://placehold.co/80x80/0066FF/FFFFFF/png"
        },
        Description: "Perpetual license for unlimited users with mobile access",
        Quantity: 1.00,
        UnitPrice: 50000.00,
        TotalPrice: 50000.00
      },
      {
        Id: "00kDS00000A3iDoYAJ",
        OpportunityId: "006DS00000NY3S9YAL",
        Product2Id: "01tDS00000JxckhYAB",
        Product2: {
          Id: "01tDS00000JxckhYAB",
          Name: "Professional Implementation",
          ImageUrl__c: "https://placehold.co/80x80/00CC66/FFFFFF/png"
        },
        Description: "4-week implementation including configuration, data migration, and integration",
        Quantity: 1.00,
        UnitPrice: 15000.00,
        TotalPrice: 15000.00
      },
      {
        Id: "00kDS00000A3iDpYAJ",
        OpportunityId: "006DS00000NY3S9YAL",
        Product2Id: "01tDS00000JxfGiYAJ",
        Product2: {
          Id: "01tDS00000JxfGiYAJ",
          Name: "Premium Support Package",
          ImageUrl__c: "https://placehold.co/80x80/FF6600/FFFFFF/png"
        },
        Description: "12-month premium support with 24/7 coverage and 1-hour response time",
        Quantity: 1.00,
        UnitPrice: 12000.00,
        TotalPrice: 12000.00
      },
      {
        Id: "00kDS00000A3iDqYAJ",
        OpportunityId: "006DS00000NY3S9YAL",
        Product2Id: "01tDS00000JxfGjYAJ",
        Product2: {
          Id: "01tDS00000JxfGjYAJ",
          Name: "Advanced Analytics Module",
          ImageUrl__c: "https://placehold.co/80x80/9900CC/FFFFFF/png"
        },
        Description: "Advanced analytics module with custom dashboards and real-time reporting",
        Quantity: 1.00,
        UnitPrice: 8000.00,
        TotalPrice: 8000.00
      },
      {
        Id: "00kDS00000A3iDrYAJ",
        OpportunityId: "006DS00000NY3S9YAL",
        Product2Id: "01tDS00000JxfGkYAJ",
        Product2: {
          Id: "01tDS00000JxfGkYAJ",
          Name: "Training & Onboarding",
          ImageUrl__c: "https://placehold.co/80x80/FF0066/FFFFFF/png"
        },
        Description: "On-site training for up to 50 users (5 days)",
        Quantity: 1.00,
        UnitPrice: 5000.00,
        TotalPrice: 5000.00
      }
    ]
  };

  Logger.log('Step 2: Preparing merge data...');
  Logger.log('DiscountPercent__c = ' + recordData.DiscountPercent__c);
  Logger.log('DiscountAmount__c = ' + recordData.DiscountAmount__c);
  Logger.log('OpportunityLineItems count = ' + childData.OpportunityLineItems.length);
  Logger.log('ORG.Phone = ' + recordData.ORG.Phone + ' (NULL - needs default value!)');
  Logger.log('');

  // Set up FormatUtils with field types metadata (for auto-formatting)
  Logger.log('Step 3: Setting up FormatUtils with field type metadata...');
  if (typeof FormatUtils !== 'undefined' && FormatUtils.setFieldTypes) {
    FormatUtils.setFieldTypes(recordData._fieldTypes);
    Logger.log('Field types loaded: ' + Object.keys(recordData._fieldTypes).length + ' fields');
  } else {
    Logger.log('⚠️  FormatUtils not available or setFieldTypes not found');
  }
  Logger.log('');

  Logger.log('Step 4: Opening test document for processing...');
  const doc = DocumentApp.openById(testDocId);
  const body = doc.getBody();

  // Check initial state
  const initialText = body.getText();
  Logger.log('Initial document contains:');
  Logger.log('  - v3.0 IF blocks: ' + (initialText.match(/\{\{IF\s+/g) || []).length);
  Logger.log('  - Contains ORG.Phone reference: ' + (initialText.indexOf('ORG.Phone') !== -1));
  Logger.log('  - Contains GrandTotal__c: ' + (initialText.indexOf('GrandTotal__c') !== -1));
  Logger.log('');
  Logger.log('NOTE: ORG.Phone is NULL in the data - template MUST have default value!');
  Logger.log('');

  // Merge parent and child data (like DocumentService does)
  const mergeData = Object.assign({}, recordData, childData);

  Logger.log('========================================');
  Logger.log('STARTING PROCESSING PIPELINE');
  Logger.log('========================================\n');

  // STEP 1: Process block-level conditionals (paragraph-only {{IF}} tags)
  Logger.log('>>> STEP 1: TemplateProcessor.processBlockLogic()');
  Logger.log('This should process conditionals that wrap tables/sections');
  Logger.log('');

  try {
    if (typeof TemplateProcessor === 'undefined') {
      Logger.log('❌ ERROR: TemplateProcessor is NOT DEFINED!');
    } else if (typeof TemplateProcessor.processBlockLogic !== 'function') {
      Logger.log('⚠️  processBlockLogic not available - using old architecture');
    } else {
      const blockCount = TemplateProcessor.processBlockLogic(body, mergeData);
      Logger.log('Block-level conditionals processed: ' + blockCount);
    }
  } catch (e) {
    Logger.log('❌ EXCEPTION in processBlockLogic: ' + e.message);
  }
  Logger.log('');

  // STEP 2: Process tables (including conditionals in table cells)
  Logger.log('>>> STEP 2: TableHandler.processTables()');
  Logger.log('This should process conditionals in table cells');
  Logger.log('');

  try {
    if (typeof TableHandler === 'undefined') {
      Logger.log('❌ ERROR: TableHandler is NOT DEFINED!');
    } else {
      const tableWarnings = TableHandler.processTables(body, childData, recordData);
      Logger.log('TableHandler completed');
      Logger.log('Warnings: ' + (tableWarnings.length > 0 ? tableWarnings.join(', ') : 'None'));

      // Check text after table processing
      const afterTables = body.getText();
      Logger.log('After TableHandler:');
      Logger.log('  - Remaining IF blocks: ' + (afterTables.match(/\{\{IF\s+/g) || []).length);

      // Look for the discount row specifically
      if (afterTables.indexOf('Discount') !== -1) {
        const discountSection = afterTables.substring(
          Math.max(0, afterTables.indexOf('Discount') - 50),
          Math.min(afterTables.length, afterTables.indexOf('Discount') + 200)
        );
        Logger.log('  - Discount section: ...' + discountSection + '...');
      }

      // Look for debug markers
      if (afterTables.indexOf('[CP_CALLED]') !== -1) {
        Logger.log('  ✅ Found [CP_CALLED] marker - ConditionalProcessor was used');
      } else {
        Logger.log('  ⚠️  No [CP_CALLED] marker - ConditionalProcessor may not have been called');
      }

      if (afterTables.indexOf('TRUEFALSE') !== -1 || afterTables.indexOf('BEFORE:TRUEFALSE') !== -1) {
        Logger.log('  ❌ FOUND "TRUEFALSE" - Both branches present!');
      } else if (afterTables.indexOf('TRUE') !== -1 && afterTables.indexOf('FALSE') === -1) {
        Logger.log('  ✅ Only TRUE branch found (FALSE not present)');
      }
    }
  } catch (e) {
    Logger.log('❌ EXCEPTION in TableHandler: ' + e.message);
    Logger.log('Stack: ' + e.stack);
  }
  Logger.log('');

  // STEP 2: Process conditionals in rest of document (should skip tables)
  Logger.log('>>> STEP 2: TemplateProcessor.processConditionals()');
  Logger.log('This should SKIP tables (already processed)');
  Logger.log('');

  try {
    if (typeof TemplateProcessor === 'undefined') {
      Logger.log('❌ ERROR: TemplateProcessor is NOT DEFINED!');
    } else {
      const conditionalWarnings = TemplateProcessor.processConditionals(body, mergeData);
      Logger.log('TemplateProcessor.processConditionals() completed');
      Logger.log('Warnings: ' + (conditionalWarnings.length > 0 ? conditionalWarnings.join(', ') : 'None'));

      // Check text after conditional processing
      const afterConditionals = body.getText();
      Logger.log('After processConditionals:');
      Logger.log('  - Remaining IF blocks: ' + (afterConditionals.match(/\{\{IF\s+/g) || []).length);

      // Look for the discount row again
      if (afterConditionals.indexOf('Discount') !== -1) {
        const discountSection = afterConditionals.substring(
          Math.max(0, afterConditionals.indexOf('Discount') - 50),
          Math.min(afterConditionals.length, afterConditionals.indexOf('Discount') + 200)
        );
        Logger.log('  - Discount section: ...' + discountSection + '...');
      }

      if (afterConditionals.indexOf('TRUEFALSE') !== -1 || afterConditionals.indexOf('BEFORE:TRUEFALSE') !== -1) {
        Logger.log('  ❌ FOUND "TRUEFALSE" after TemplateProcessor - double processing occurred!');
      } else if (afterConditionals.indexOf('TRUE') !== -1 && afterConditionals.indexOf('FALSE') === -1) {
        Logger.log('  ✅ Still only TRUE branch (FALSE not present)');
      }
    }
  } catch (e) {
    Logger.log('❌ EXCEPTION in TemplateProcessor: ' + e.message);
    Logger.log('Stack: ' + e.stack);
  }
  Logger.log('');

  // STEP 3: Process simple fields
  Logger.log('>>> STEP 3: TemplateProcessor.processFields()');
  Logger.log('');

  try {
    TemplateProcessor.processFields(body, mergeData);
    Logger.log('Simple fields processed');
  } catch (e) {
    Logger.log('❌ EXCEPTION in processFields: ' + e.message);
  }
  Logger.log('');

  // Final state
  Logger.log('========================================');
  Logger.log('FINAL RESULT');
  Logger.log('========================================\n');

  const finalText = body.getText();

  // Check for key content from professional invoice template
  Logger.log('Checking processed content...');

  // Check HIGH VALUE indicator (GrandTotal > 50000)
  if (finalText.indexOf('HIGH VALUE INVOICE') !== -1) {
    Logger.log('  ✅ High value indicator shown correctly');
  } else if (finalText.indexOf('Standard Invoice') !== -1) {
    Logger.log('  ⚠️  Standard invoice shown (should be HIGH VALUE)');
  } else {
    Logger.log('  ❌ Conditional not processed properly');
  }

  // Check discount row (should show since DiscountPercent__c = 5.0)
  if (finalText.indexOf('Discount (5.0%)') !== -1 && finalText.indexOf('No Discount') === -1) {
    Logger.log('  ✅ Discount row correct (only Discount shown)');
  } else if (finalText.indexOf('No Discount') !== -1 && finalText.indexOf('Discount (') === -1) {
    Logger.log('  ❌ Wrong: Only "No Discount" shown (should show Discount)');
  } else if (finalText.indexOf('Discount') !== -1 && finalText.indexOf('No Discount') !== -1) {
    Logger.log('  ❌ BOTH BRANCHES PRESENT: Conditional not working!');
  }

  // Check for line items table
  const lineItemsCount = (finalText.match(/Enterprise Platform License/g) || []).length;
  Logger.log('  Line items processed: ' + lineItemsCount + ' products found');

  // Check for cases data source
  const casesCount = (finalText.match(/00001\d+/g) || []).length;
  Logger.log('  Open cases processed: ' + casesCount + ' cases found');

  // Check if ORG.Phone was handled (should have default value in template)
  if (finalText.indexOf('Field not found: ORG.Phone') !== -1) {
    Logger.log('  ❌ ORG.Phone error - template needs default value!');
  } else if (finalText.indexOf('ORG.Phone') === -1) {
    Logger.log('  ✅ ORG.Phone processed correctly (with default or skipped)');
  } else {
    Logger.log('  ⚠️  ORG.Phone placeholder still present');
  }

  Logger.log('');

  Logger.log('Test document URL:');
  Logger.log('https://docs.google.com/document/d/' + testDocId + '/edit');
  Logger.log('');
  Logger.log('Open this URL to see the actual processed document!');
  Logger.log('');
  Logger.log('========================================');
  Logger.log('TEST COMPLETE');
  Logger.log('========================================');
}

/**
 * Test just the TableHandler processing with detailed logging
 */
function testTableHandlerOnly() {
  Logger.log('=== TESTING TableHandler.replaceFieldsInText() ===\n');

  const testData = {
    DiscountPercent__c: 5.00,
    DiscountAmount__c: 4500.00,
    GrandTotal__c: 93150.00
  };

  const testCases = [
    // v3.0 syntax tests
    '{{IF DiscountPercent__c}}Discount ({{DiscountPercent__c:percent}}){{ELSE}}No Discount{{/IF}}',
    '{{IF NOT ISBLANK DiscountAmount__c}}-{{DiscountAmount__c:currency}}{{ELSE}}$0.00{{/IF}}',
    '{{IF GrandTotal__c > 50000}}HIGH VALUE{{ELSE}}Standard{{/IF}}'
  ];

  Logger.log('Test Data: ' + JSON.stringify(testData));
  Logger.log('');

  if (typeof TableHandler === 'undefined') {
    Logger.log('❌ ERROR: TableHandler is NOT DEFINED!');
    return;
  }

  for (let i = 0; i < testCases.length; i++) {
    const input = testCases[i];
    Logger.log('Test ' + (i + 1) + ':');
    Logger.log('Input:  ' + input);

    try {
      const result = TableHandler.replaceFieldsInText(input, testData);
      Logger.log('Result: ' + result);

      // Check for issues
      if (result.indexOf('TRUEFALSE') !== -1) {
        Logger.log('❌ BOTH BRANCHES APPEARED!');
      } else if (result.indexOf('[CP_CALLED]') !== -1) {
        Logger.log('✅ ConditionalProcessor was called');
      } else if (result.indexOf('[ERROR:CP_NOT_DEFINED]') !== -1) {
        Logger.log('❌ ConditionalProcessor NOT DEFINED');
      }
    } catch (e) {
      Logger.log('❌ EXCEPTION: ' + e.message);
    }
    Logger.log('');
  }

  Logger.log('=== TEST COMPLETE ===');
}
