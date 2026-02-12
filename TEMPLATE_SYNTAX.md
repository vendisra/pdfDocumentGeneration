# Template Syntax Reference

**Version 3.0** - Complete guide for document template authors

This document provides comprehensive syntax reference for creating Google Docs templates for Salesforce document generation.

---

## Table of Contents

1. [Field References](#field-references)
2. [Format Directives](#format-directives)
3. [Default Values](#default-values)
4. [Conditionals](#conditionals)
5. [Repeater Sections](#repeater-sections)
6. [Images](#images)
7. [Page Breaks](#page-breaks)
8. [Expression Operators](#expression-operators)
9. [Common Patterns](#common-patterns)
10. [Error Messages](#error-messages)

---

## Field References

### Basic Syntax
```
{{FieldName}}
```

**Examples:**
```
{{Name}}
{{Amount}}
{{CloseDate}}
{{IsActive}}
```

### Related Fields (Dot Notation)
Access fields from related objects using dot notation. Supports multiple levels.

```
{{RelatedObject.FieldName}}
{{RelatedObject.ParentObject.FieldName}}
```

**Examples:**
```
{{Account.Name}}
{{Account.Owner.Name}}
{{Account.Parent.Name}}
{{Account.Parent.Parent.Name}}
```

### System Variables
Pre-populated system variables:

```
{{TODAY}}              - Current date
{{NOW}}                - Current date and time
{{CURRENT_USER.Name}}  - Current user's name
{{ORG.Name}}           - Organization name
{{ORG.Street}}         - Organization street
{{ORG.City}}           - Organization city
{{ORG.State}}          - Organization state
{{ORG.PostalCode}}     - Organization postal code
{{ORG.Phone}}          - Organization phone
```

---

## Format Directives

Apply formatting to field values using the colon (`:`) syntax:

```
{{FieldName:format}}
```

### Available Formats

| Format | Description | Example Input | Example Output |
|--------|-------------|---------------|----------------|
| `currency` | USD currency | `1234.56` | `$1,234.56` |
| `number` | Thousands separator | `1234567` | `1,234,567` |
| `percent` | Percentage | `0.25` or `25` | `25.0%` |
| `date` | Long date | `2024-01-15` | `January 15, 2024` |
| `datetime` | Date and time | `2024-01-15T14:30` | `January 15, 2024 2:30 PM` |
| `time` | Time only | `14:30:00` | `2:30 PM` |
| `phone` | Phone number | `4155551234` | `(415) 555-1234` |
| `boolean` | Yes/No | `true` | `Yes` |
| `uppercase` | UPPERCASE TEXT | `hello` | `HELLO` |
| `lowercase` | lowercase text | `HELLO` | `hello` |
| `capitalize` | Title Case | `hello world` | `Hello World` |
| `2` (number) | Decimal places | `3.14159` | `3.14` |

**Examples:**
```
{{Amount:currency}}          → $1,234.56
{{CloseDate:date}}           → January 15, 2024
{{Phone:phone}}              → (415) 555-1234
{{IsActive:boolean}}         → Yes
{{Name:uppercase}}           → JOHN DOE
{{DiscountRate:percent}}     → 15.0%
{{Price:2}}                  → 99.99
```

### Auto-Formatting
Salesforce field types are automatically formatted without explicit format directives:
- Currency fields → `$1,234.56`
- Date fields → `January 15, 2024`
- DateTime fields → `January 15, 2024 2:30 PM`
- Percent fields → `25.0%`
- Phone fields → `(415) 555-1234`
- Boolean fields → `Yes/No`

---

## Default Values

Provide fallback values when fields are missing or null:

```
{{FieldName ?? 'default value'}}
```

**Examples:**
```
{{Account.Name ?? 'Unknown Account'}}
{{Amount:currency ?? '$0.00'}}
{{Description ?? 'No description provided'}}
{{Owner.Name ?? 'Unassigned'}}
```

### With Formatting
Combine default values with format directives:

```
{{Amount:currency ?? '$0.00'}}
{{CloseDate:date ?? 'TBD'}}
{{DiscountPercent:percent ?? '0%'}}
```

**Important:** If a field is missing and no default is provided, document generation will **fail** with an error.

---

## Conditionals

Control content visibility based on conditions.

### Basic IF Statement
```
{{IF condition}}
  Content shown when condition is true
{{/IF}}
```

### IF-ELSE Statement
```
{{IF condition}}
  Content shown when true
{{ELSE}}
  Content shown when false
{{/IF}}
```

### IF-ELSEIF-ELSE Statement
```
{{IF condition1}}
  Content for condition1
{{ELSEIF condition2}}
  Content for condition2
{{ELSEIF condition3}}
  Content for condition3
{{ELSE}}
  Default content
{{/IF}}
```

### Nested Conditionals
```
{{IF Stage == 'Closed Won'}}
  Deal is won!
  {{IF Amount > 100000}}
    High-value deal!
  {{ELSE}}
    Standard deal
  {{/IF}}
{{/IF}}
```

---

## Repeater Sections

Repeat content for each record in a collection.

### Child Relationships
Use `{{#RelationshipName}}` for Salesforce child relationships:

```
{{#OpportunityLineItems}}
  Product: {{Product2.Name}}
  Quantity: {{Quantity}}
  Price: {{UnitPrice:currency}}
  Total: {{TotalPrice:currency}}
{{/OpportunityLineItems}}
```

### Data Sources
Use `{{@AliasName}}` for configured data sources (from TemplateDataSource__c):

```
{{@OpenCases}}
  Case: {{CaseNumber}}
  Subject: {{Subject}}
  Status: {{Status}}
  Priority: {{Priority}}
{{/@OpenCases}}
```

### Repeaters in Tables
Tables automatically repeat rows for each record:

```
| # | Product | Qty | Price | Total |
|---|---------|-----|-------|-------|
| {{#OpportunityLineItems}}{{ROW_NUM}} | {{Product2.Name}} | {{Quantity}} | {{UnitPrice:currency}} | {{TotalPrice:currency}}{{/OpportunityLineItems}} |
```

### Special Variables in Repeaters
- `{{ROW_NUM}}` - Row number (1-indexed)
- `{{ROW_INDEX}}` - Row index (0-indexed)
- `{{PARENT_ROW_NUM}}` - Parent row number (for nested repeaters)

### Nested Repeaters
```
{{#Opportunities}}
  Opportunity: {{Name}}
  {{#OpportunityLineItems}}
    - {{Product2.Name}}: {{TotalPrice:currency}}
  {{/OpportunityLineItems}}
{{/Opportunities}}
```

---

## Images

Insert images from URL fields.

### Basic Syntax
```
{{IMAGE:FieldName}}
```

### With Dimensions
```
{{IMAGE:FieldName:widthxheight}}
```

**Examples:**
```
{{IMAGE:CompanyLogoUrl__c}}
{{IMAGE:CompanyLogoUrl__c:200x100}}
{{IMAGE:Product2.ImageUrl__c:150x150}}
```

**Requirements:**
- Image URL must be publicly accessible (no authentication)
- Supported formats: JPG, PNG, GIF, WebP, SVG
- Maximum dimensions: 800x800 pixels

---

## Page Breaks

Insert page breaks in the document:

```
{{PAGE_BREAK}}
```

**Example:**
```
... content for page 1 ...

{{PAGE_BREAK}}

... content for page 2 ...
```

---

## Expression Operators

### Comparison Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equal to | `Status == 'Won'` |
| `!=` | Not equal to | `Status != 'Lost'` |
| `>` | Greater than | `Amount > 10000` |
| `<` | Less than | `Amount < 5000` |
| `>=` | Greater or equal | `Amount >= 10000` |
| `<=` | Less or equal | `Amount <= 5000` |

### String Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `CONTAINS` | Contains substring | `Description CONTAINS 'urgent'` |
| `STARTSWITH` | Starts with | `Email STARTSWITH 'admin'` |
| `ENDSWITH` | Ends with | `Filename ENDSWITH '.pdf'` |
| `ISBLANK` | Field is blank/null | `ISBLANK Description` |
| `IEQUALS` | Case-insensitive equals | `Status IEQUALS 'won'` |

### Logical Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `AND` | Both conditions true | `Status == 'Won' AND Amount > 10000` |
| `OR` | Either condition true | `Status == 'Won' OR Status == 'Closed'` |
| `NOT` | Negates condition | `NOT IsDeleted` |
| `()` | Grouping | `(A AND B) OR (C AND D)` |

### Expression Examples

```
{{IF Status == 'Won' AND Amount > 50000}}
  High-value win!
{{/IF}}

{{IF Description CONTAINS 'urgent' OR Priority == 'High'}}
  ⚠️ Urgent
{{/IF}}

{{IF Email STARTSWITH 'admin' AND NOT ISBLANK Department}}
  Admin user: {{Name}} ({{Department}})
{{/IF}}

{{IF Status IEQUALS 'won'}}
  (Matches 'Won', 'WON', 'won')
{{/IF}}

{{IF (Stage == 'Prospecting' OR Stage == 'Qualification') AND Amount > 5000}}
  Early stage, high value
{{/IF}}
```

---

## Common Patterns

### Conditional Field Display
```
{{IF Account.Phone}}
  Phone: {{Account.Phone:phone}}
{{/IF}}
```

### Conditional Sections
```
{{IF ISBLANK BillingNotes__c}}
  No special billing notes
{{ELSE}}
  Billing Notes:
  {{BillingNotes__c}}
{{/IF}}
```

### Conditional Formatting
```
{{IF Amount > 100000}}
  *** HIGH VALUE ***
{{/IF}}
Amount: {{Amount:currency}}
```

### Multi-Condition Branching
```
{{IF Priority == 'Critical'}}
  🔴 CRITICAL
{{ELSEIF Priority == 'High'}}
  🟠 HIGH
{{ELSEIF Priority == 'Medium'}}
  🟡 MEDIUM
{{ELSE}}
  🟢 LOW
{{/IF}}
```

### Table with Conditionals
```
| # | Product | Status | Price |
|---|---------|--------|-------|
| {{#Items}}{{ROW_NUM}} | {{Name}} | {{IF IsActive}}✓ Active{{ELSE}}Inactive{{/IF}} | {{IF Price > 1000}}{{Price:currency}} (Premium){{ELSE}}{{Price:currency}}{{/IF}}{{/Items}} |
```

### Nested Data
```
{{#Accounts}}
  Account: {{Name}}

  Open Opportunities:
  {{#Opportunities}}
    - {{Name}}: {{Amount:currency}}
  {{/Opportunities}}
{{/Accounts}}
```

---

## Error Messages

Understanding error messages helps you fix templates quickly.

### Field Not Found
```
Error: Field not found: CustomField__c (use {{CustomField__c ?? 'default'}} to provide a default value)
```

**Solution:** Either add the field to your data query or provide a default value:
```
{{CustomField__c ?? 'N/A'}}
```

### No Data for Section
```
Error: No data for table section: LineItems
```

**Solution:** Ensure the child relationship or data source has records, or handle with conditionals:
```
{{IF LineItems}}
  {{#LineItems}}
    ...
  {{/LineItems}}
{{ELSE}}
  No line items
{{/IF}}
```

### Conditional Evaluation Failed
```
Error: Conditional evaluation failed for "Status = 'Won'": Expected '==' operator
```

**Solution:** Use correct operator syntax (double equals):
```
{{IF Status == 'Won'}}
```

### Unclosed Section
```
Error: Unclosed section: {{#LineItems}}
```

**Solution:** Ensure every opening tag has a closing tag:
```
{{#LineItems}}
  ...
{{/LineItems}}
```

### Invalid Expression
```
Error: Expected value after operator
```

**Solution:** Ensure complete expressions:
```
{{IF Amount > 1000}}  ✓ Correct
{{IF Amount >}}       ✗ Incorrect
```

---

## Best Practices

### 1. Always Provide Defaults for Optional Fields
```
{{OptionalField ?? 'N/A'}}
```

### 2. Use Descriptive Field Names in Templates
```
<!-- Good -->
{{Account.Name}}
{{Opportunity.Amount:currency}}

<!-- Avoid -->
{{a.n}}
{{o.amt}}
```

### 3. Format Dates and Currency Consistently
```
{{CloseDate:date}}
{{Amount:currency}}
```

### 4. Use Comments for Complex Logic
```
<!-- Check if high-value AND urgent -->
{{IF Amount > 50000 AND Priority == 'High'}}
  ...
{{/IF}}
```

### 5. Test with Missing Data
Ensure templates handle missing fields gracefully:
```
{{OptionalDescription ?? 'No description provided'}}
```

### 6. Use ELSEIF for Multiple Conditions
```
<!-- Good -->
{{IF Status == 'Won'}}
  Won
{{ELSEIF Status == 'Lost'}}
  Lost
{{ELSE}}
  Open
{{/IF}}

<!-- Avoid nested IFs when ELSEIF works -->
{{IF Status == 'Won'}}
  Won
{{ELSE}}
  {{IF Status == 'Lost'}}
    Lost
  {{ELSE}}
    Open
  {{/IF}}
{{/IF}}
```

---

## Quick Reference Card

```
# Fields
{{FieldName}}
{{Object.Field}}
{{Field:format}}
{{Field ?? 'default'}}

# Conditionals
{{IF condition}}...{{/IF}}
{{IF condition}}...{{ELSE}}...{{/IF}}
{{IF c1}}...{{ELSEIF c2}}...{{ELSE}}...{{/IF}}

# Repeaters
{{#ChildRelationship}}...{{/ChildRelationship}}
{{@DataSourceAlias}}...{{/@DataSourceAlias}}

# Special
{{IMAGE:Field}}
{{IMAGE:Field:200x150}}
{{PAGE_BREAK}}
{{ROW_NUM}}

# Operators
==  !=  >  <  >=  <=
AND  OR  NOT  ()
CONTAINS  STARTSWITH  ENDSWITH  ISBLANK  IEQUALS
```

---

## Support

For issues or questions:
- Check error messages carefully - they guide you to the problem
- Review examples in this document
- Test templates with sample data before production use
- Document generation fails fast on errors - no partial documents

---

**Document Version:** 3.0
**Last Updated:** January 2026
**Framework:** Google Apps Script Document Generation for Salesforce
