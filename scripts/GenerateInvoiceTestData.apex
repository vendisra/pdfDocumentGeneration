/**
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║  PROFESSIONAL INVOICE - Test Data Generator                                 ║
 * ╠══════════════════════════════════════════════════════════════════════════════╣
 * ║  Purpose:   Create realistic invoice data for production demos              ║
 * ║  Template:  ProfessionalInvoice (create in GAS)                             ║
 * ║  Object:    Opportunity (used as Invoice)                                   ║
 * ║  Features:  80% framework coverage in real business context                 ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 */

String PREFIX = 'INV';

// ──────────────────────────────────────────────────────────────────────────────
// STEP 1: CLEANUP
// ──────────────────────────────────────────────────────────────────────────────
delete [SELECT Id FROM Opportunity WHERE Name LIKE :PREFIX + '%' LIMIT 100];
delete [SELECT Id FROM Case WHERE Account.Name LIKE :PREFIX + '%' LIMIT 100];
delete [SELECT Id FROM Contact WHERE Account.Name LIKE :PREFIX + '%' LIMIT 100];
delete [SELECT Id FROM Account WHERE Name LIKE :PREFIX + '%' ORDER BY ParentId DESC NULLS LAST LIMIT 100];

// ──────────────────────────────────────────────────────────────────────────────
// STEP 2: CREATE ACCOUNT HIERARCHY
// ──────────────────────────────────────────────────────────────────────────────

Account grandparent = new Account(
    Name = PREFIX + ' Global Holdings',
    Industry = 'Technology',
    Phone = '(800) 555-0001',
    Website = 'www.globalholdings.example.com',
    BillingStreet = '100 Corporate Plaza',
    BillingCity = 'New York',
    BillingState = 'NY',
    BillingPostalCode = '10001',
    BillingCountry = 'USA'
);
insert grandparent;

Account parent = new Account(
    Name = PREFIX + ' North America Inc',
    ParentId = grandparent.Id,
    Industry = 'Technology',
    Phone = '(415) 555-0100',
    Website = 'www.northamerica.example.com',
    BillingStreet = '500 Market Street, Suite 1200',
    BillingCity = 'San Francisco',
    BillingState = 'CA',
    BillingPostalCode = '94105',
    BillingCountry = 'USA'
);
insert parent;

Account customer = new Account(
    Name = PREFIX + ' Enterprise Solutions',
    ParentId = parent.Id,
    Industry = 'Manufacturing',
    Phone = '(555) 200-1234',
    Fax = '(555) 200-1235',
    Website = 'www.enterprise.example.com',
    BillingStreet = '123 Innovation Drive, Building A',
    BillingCity = 'Austin',
    BillingState = 'TX',
    BillingPostalCode = '78701',
    BillingCountry = 'USA'
);
insert customer;

// ──────────────────────────────────────────────────────────────────────────────
// STEP 3: CREATE BILLING CONTACT
// ──────────────────────────────────────────────────────────────────────────────

Contact billingContact = new Contact(
    AccountId = customer.Id,
    FirstName = 'Sarah',
    LastName = 'Johnson',
    Title = 'VP of Finance',
    Email = 'sarah.johnson@enterprise.example.com',
    Phone = '(555) 200-1240',
    MobilePhone = '(555) 200-1241'
);
insert billingContact;

// ──────────────────────────────────────────────────────────────────────────────
// STEP 4: CREATE PRODUCTS
// ──────────────────────────────────────────────────────────────────────────────

List<Product2> products = new List<Product2>{
    new Product2(
        Name = 'Enterprise Platform License',
        ProductCode = 'EPL-1000',
        IsActive = true,
        Description = 'Full-featured enterprise platform with unlimited users',
        ImageUrl__c = 'https://placehold.co/80x80/0066FF/FFFFFF/png'
    ),
    new Product2(
        Name = 'Professional Implementation',
        ProductCode = 'IMPL-500',
        IsActive = true,
        Description = 'Expert implementation services including data migration',
        ImageUrl__c = 'https://placehold.co/80x80/00CC66/FFFFFF/png'
    ),
    new Product2(
        Name = 'Premium Support Package',
        ProductCode = 'SUP-PREM',
        IsActive = true,
        Description = '24/7 premium support with 1-hour response SLA',
        ImageUrl__c = 'https://placehold.co/80x80/FF6600/FFFFFF/png'
    ),
    new Product2(
        Name = 'Advanced Analytics Module',
        ProductCode = 'ANA-ADV',
        IsActive = true,
        Description = 'Real-time analytics and reporting dashboards',
        ImageUrl__c = 'https://placehold.co/80x80/9900CC/FFFFFF/png'
    ),
    new Product2(
        Name = 'Training & Onboarding',
        ProductCode = 'TRN-1000',
        IsActive = true,
        Description = 'Comprehensive training for up to 50 users',
        ImageUrl__c = 'https://placehold.co/80x80/FF0066/FFFFFF/png'
    )
};
insert products;

// ──────────────────────────────────────────────────────────────────────────────
// STEP 5: CREATE PRICEBOOK ENTRIES
// ──────────────────────────────────────────────────────────────────────────────

Id stdPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

List<PricebookEntry> pbes = new List<PricebookEntry>{
    new PricebookEntry(Pricebook2Id = stdPricebookId, Product2Id = products[0].Id, UnitPrice = 50000, IsActive = true),
    new PricebookEntry(Pricebook2Id = stdPricebookId, Product2Id = products[1].Id, UnitPrice = 15000, IsActive = true),
    new PricebookEntry(Pricebook2Id = stdPricebookId, Product2Id = products[2].Id, UnitPrice = 12000, IsActive = true),
    new PricebookEntry(Pricebook2Id = stdPricebookId, Product2Id = products[3].Id, UnitPrice = 8000, IsActive = true),
    new PricebookEntry(Pricebook2Id = stdPricebookId, Product2Id = products[4].Id, UnitPrice = 5000, IsActive = true)
};
insert pbes;

// ──────────────────────────────────────────────────────────────────────────────
// STEP 6: CREATE OPPORTUNITY (as Invoice)
// ──────────────────────────────────────────────────────────────────────────────

Decimal subtotal = 90000.00;
Decimal taxRate = 8.5;
Decimal taxAmount = subtotal * (taxRate / 100);
Decimal discountPercent = 5.0;
Decimal discountAmount = subtotal * (discountPercent / 100);
Decimal grandTotal = subtotal + taxAmount - discountAmount;

Opportunity invoice = new Opportunity(
    Name = PREFIX + '-2024-001 - Enterprise Platform Implementation',
    AccountId = customer.Id,
    StageName = 'Closed Won',
    CloseDate = Date.today(),
    Pricebook2Id = stdPricebookId,
    Amount = grandTotal,
    Description = 'Complete enterprise platform implementation including licensing, professional services, support, analytics, and training.',
    LeadSource = 'Referral',
    Type = 'New Business',
    
    // Custom fields for Invoice
    InvoiceNumber__c = 'INV-2024-0001',
    InvoiceDate__c = Date.today(),
    DueDate__c = Date.today().addDays(30),
    PaymentTerms__c = 'Net 30',
    PaymentMethod__c = 'Wire Transfer',
    SubTotal__c = subtotal,
    TaxRate__c = taxRate,
    TaxAmount__c = taxAmount,
    DiscountPercent__c = discountPercent,
    DiscountAmount__c = discountAmount,
    GrandTotal__c = grandTotal,
    BillingNotes__c = 'Early payment discount available: 2% if paid within 10 days.',
    BankName__c = 'First National Bank',
    BankAccountNumber__c = '****1234',
    BankRoutingNumber__c = '123456789',
    BankSwiftCode__c = 'FNBAUS33XXX',
    CompanyLogoUrl__c = 'https://placehold.co/200x80/0066FF/FFFFFF/png'
);
insert invoice;

// ──────────────────────────────────────────────────────────────────────────────
// STEP 7: CREATE LINE ITEMS
// ──────────────────────────────────────────────────────────────────────────────

List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>{
    new OpportunityLineItem(
        OpportunityId = invoice.Id,
        PricebookEntryId = pbes[0].Id,
        Quantity = 1,
        UnitPrice = 50000,
        Description = 'Perpetual license for unlimited users with mobile access'
    ),
    new OpportunityLineItem(
        OpportunityId = invoice.Id,
        PricebookEntryId = pbes[1].Id,
        Quantity = 1,
        UnitPrice = 15000,
        Description = '4-week implementation including configuration, data migration, and integration'
    ),
    new OpportunityLineItem(
        OpportunityId = invoice.Id,
        PricebookEntryId = pbes[2].Id,
        Quantity = 1,
        UnitPrice = 12000,
        Description = '12-month premium support with 24/7 coverage and 1-hour response time'
    ),
    new OpportunityLineItem(
        OpportunityId = invoice.Id,
        PricebookEntryId = pbes[3].Id,
        Quantity = 1,
        UnitPrice = 8000,
        Description = 'Advanced analytics module with custom dashboards and real-time reporting'
    ),
    new OpportunityLineItem(
        OpportunityId = invoice.Id,
        PricebookEntryId = pbes[4].Id,
        Quantity = 1,
        UnitPrice = 5000,
        Description = 'On-site training for up to 50 users (5 days)'
    )
};
insert lineItems;

// ──────────────────────────────────────────────────────────────────────────────
// STEP 8: CREATE RELATED CASES (for data source testing)
// ──────────────────────────────────────────────────────────────────────────────

List<Case> cases = new List<Case>{
    new Case(
        AccountId = customer.Id,
        ContactId = billingContact.Id,
        Subject = 'Pre-implementation technical review',
        Status = 'Closed',
        Priority = 'High',
        Origin = 'Email',
        Description = 'Technical architecture review completed before implementation start.'
    ),
    new Case(
        AccountId = customer.Id,
        ContactId = billingContact.Id,
        Subject = 'Integration requirements discussion',
        Status = 'Working',
        Priority = 'Medium',
        Origin = 'Phone',
        Description = 'Ongoing discussion about API integrations with existing systems.'
    ),
    new Case(
        AccountId = customer.Id,
        ContactId = billingContact.Id,
        Subject = 'Data migration planning',
        Status = 'New',
        Priority = 'High',
        Origin = 'Email',
        Description = 'Planning the data migration from legacy systems to the new platform.'
    ),
    new Case(
        AccountId = customer.Id,
        ContactId = billingContact.Id,
        Subject = 'Training schedule coordination',
        Status = 'New',
        Priority = 'Low',
        Origin = 'Web',
        Description = 'Coordinating training schedules for 50 users across multiple time zones.'
    )
};
insert cases;

// ──────────────────────────────────────────────────────────────────────────────
// BONUS: CREATE DATA SOURCE CONFIGURATION (if template exists)
// ──────────────────────────────────────────────────────────────────────────────

List<DocumentTemplate__c> templates = [
    SELECT Id, Name FROM DocumentTemplate__c 
    WHERE Name = 'ProfessionalInvoice'
    AND IsActive__c = true
    LIMIT 1
];

if (!templates.isEmpty()) {
    // Check if data source already exists
    List<TemplateDataSource__c> existingDS = [
        SELECT Id FROM TemplateDataSource__c 
        WHERE DocumentTemplate__c = :templates[0].Id 
        AND Alias__c = 'OpenCases'
        LIMIT 1
    ];
    
    if (existingDS.isEmpty()) {
        TemplateDataSource__c openCasesDS = new TemplateDataSource__c(
            DocumentTemplate__c = templates[0].Id,
            Alias__c = 'OpenCases',
            ObjectApiName__c = 'Case',
            FilterCondition__c = 'AccountId = :AccountId AND IsClosed = false',
            FieldList__c = 'Id, CaseNumber, Subject, Status, Priority, CreatedDate, LastModifiedDate',
            OrderBy__c = 'CreatedDate DESC',
            RecordLimit__c = 10,
            IsActive__c = true,
            SortOrder__c = 1,
            Description__c = 'Open support cases for the customer account'
        );
        insert openCasesDS;
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// FINAL OUTPUT
// ──────────────────────────────────────────────────────────────────────────────
Opportunity result = [
    SELECT Id, Name, Account.Name, Account.Parent.Name, Account.Parent.Parent.Name, Amount
    FROM Opportunity 
    WHERE Id = :invoice.Id
];

System.debug('Test data created. Invoice Id: ' + result.Id + ', Line Items: ' +
             lineItems.size() + ', Cases: ' + cases.size());
