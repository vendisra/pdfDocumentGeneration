/**
 * TableHandler - Dynamic table/repeater processing
 * Version 1.0
 */
const TableHandler = {

  MAX_TABLE_ROWS: 100,
  BATCH_SIZE: 20,

  processTables: function(body, childData, parentData) {
    const startTime = Date.now();
    const warnings = [];

    // Find all tables in the document
    const tables = this.findAllTables(body);

    for (const table of tables) {
      this.processTable(table, childData, parentData);

      // Check execution time
      if (Date.now() - startTime > 300000) { // 5 minutes
        throw new Error('Table processing timeout limit exceeded (5 minutes)');
      }
    }

    // Also process inline repeaters (non-table sections)
    this.processInlineRepeaters(body, childData, parentData);

    return warnings;
  },

  findAllTables: function(body) {
    const tables = [];
    const numChildren = body.getNumChildren();

    for (let i = 0; i < numChildren; i++) {
      const child = body.getChild(i);
      if (child.getType() === DocumentApp.ElementType.TABLE) {
        tables.push(child.asTable());
      }
    }

    return tables;
  },

  processTable: function(table, childData, parentData) {
    // Check if table has a repeater section marker
    const numRows = table.getNumRows();
    if (numRows < 2) return;

    // Look for section markers in the table
    const { sectionName, templateRowIndex } = this.findSectionMarker(table);

    if (!sectionName) {
      // No repeater in this table, do simple field replacement
      this.replaceFieldsInTable(table, parentData);
      return;
    }

    // Check childData first (for child relationships like LineItems)
    // then parentData (for cross-object queries like RelatedRecords)
    let records = childData[sectionName];
    if (!records || !Array.isArray(records)) {
      records = parentData && parentData[sectionName];
    }

    if (!records || !Array.isArray(records) || records.length === 0) {
      throw new Error('No data for table section: ' + sectionName);
    }

    // Check for large datasets
    if (records.length > this.MAX_TABLE_ROWS) {
      logWarn(`Large table: ${sectionName} has ${records.length} rows. Consider pagination.`);
    }

    // Process the repeater with optimized batching
    this.processTableRepeaterOptimized(table, templateRowIndex, records, sectionName, parentData);
  },

  /**
   * Finds section marker in table and returns section name and row index
   * Supports both {{#SectionName}} and {{@DataSourceAlias}} syntax
   * IMPORTANT: Skips conditional markers ({{#IF}}) - those are NOT section markers
   */
  findSectionMarker: function(table) {
    const numRows = table.getNumRows();

    for (let i = 0; i < numRows; i++) {
      const rowText = this.getRowText(table.getRow(i));

      // Try new data source syntax first: {{@Alias}}
      let match = rowText.match(/\{\{@([^}]+)\}\}/);
      if (match) {
        return { sectionName: match[1].trim(), templateRowIndex: i, isDataSource: true };
      }

      // Fall back to standard syntax: {{#SectionName}}
      match = rowText.match(/\{\{#([^}]+)\}\}/);
      if (match) {
        const sectionName = match[1].trim();
        return { sectionName: sectionName, templateRowIndex: i, isDataSource: false };
      }
    }

    return { sectionName: null, templateRowIndex: -1, isDataSource: false };
  },

  /**
   * Removes template row when no data available
   */
  removeTemplateRow: function(table, rowIndex, sectionName) {
    if (rowIndex >= 0 && rowIndex < table.getNumRows()) {
      // Clean markers first, then optionally remove row
      const row = table.getRow(rowIndex);
      this.cleanSectionMarkers(row, sectionName);
      // Keep row but clear content to show "no items" state
      // Alternatively: table.removeRow(rowIndex);
    }
  },

  /**
   * Processes a table repeater section with optimized batching
   * Uses bulk attribute operations (getAttributes/setAttributes) for performance
   */
  processTableRepeaterOptimized: function(table, templateRowIndex, records, sectionName, parentData) {
    const templateRow = table.getRow(templateRowIndex);

    // Clean section markers from template
    this.cleanSectionMarkers(templateRow, sectionName);

    // Capture row attributes in bulk once (not per row)
    const templateRowAttributes = templateRow.getAttributes();

    // Get template row structure (cells and their text)
    const templateCells = this.captureRowTemplate(templateRow);

    // Process first record using template row
    if (records.length > 0) {
      const firstRowData = { ...parentData, ...records[0], ROW_NUM: 1, ROW_INDEX: 0 };
      this.fillRowFromTemplate(templateRow, templateCells, firstRowData, templateRowAttributes);
    }

    // Add remaining rows
    for (let i = 1; i < records.length; i++) {
      const record = records[i];
      const rowData = { ...parentData, ...record, ROW_NUM: i + 1, ROW_INDEX: i };

      // Insert new row after template (position shifts as we add)
      const newRow = table.insertTableRow(templateRowIndex + i);

      // Apply bulk attributes to new row, then fill with data
      this.fillRowFromTemplate(newRow, templateCells, rowData, templateRowAttributes, true);
    }

    // Process images in the table rows after all text replacement is done
    // This allows IMAGE markers to work properly in repeater rows
    this.processImagesInTable(table, parentData, records);
  },

  /**
   * Processes images in table cells after text replacement
   * This is called AFTER all rows are created and text is filled
   * @param {GoogleAppsScript.Document.Table} table - The table element
   * @param {Object} parentData - Parent record data
   * @param {Array} records - Array of child records
   */
  processImagesInTable: function(table, parentData, records) {
    try {
      // Scan each row for IMAGE markers
      const numRows = table.getNumRows();

      for (let r = 0; r < numRows; r++) {
        const row = table.getRow(r);
        const numCells = row.getNumCells();

        // Determine which record this row corresponds to
        // Row 0 is typically header, data rows start at 1
        const recordIndex = r - 1; // Assuming row 0 is header
        const rowData = recordIndex >= 0 && recordIndex < records.length
          ? { ...parentData, ...records[recordIndex], ROW_NUM: recordIndex + 1, ROW_INDEX: recordIndex }
          : parentData;

        for (let c = 0; c < numCells; c++) {
          const cell = row.getCell(c);
          const cellText = cell.getText();

          // Check if cell contains IMAGE marker
          if (/\{\{IMAGE:/i.test(cellText)) {
            this.processImageInCell(cell, cellText, rowData);
          }
        }
      }
    } catch (error) {
      logWarn('Failed to process images in table: ' + error.message);
    }
  },

  /**
   * Processes a single IMAGE marker in a table cell
   * @param {GoogleAppsScript.Document.TableCell} cell - The table cell
   * @param {string} cellText - Current cell text
   * @param {Object} rowData - Data for this row
   */
  processImageInCell: function(cell, cellText, rowData) {
    try {
      // Parse IMAGE marker
      const imagePattern = /\{\{IMAGE:([^}:]+)(?::(\d+)x(\d+))?\}\}/gi;
      const match = imagePattern.exec(cellText);

      if (!match) {
        return;
      }

      const fieldName = match[1].trim();
      const width = match[2] ? parseInt(match[2]) : ImageHandler.DEFAULT_WIDTH;
      const height = match[3] ? parseInt(match[3]) : ImageHandler.DEFAULT_HEIGHT;

      // Resolve image URL
      const imageUrl = TemplateProcessor.resolveValue(fieldName, rowData);

      if (!imageUrl || !ImageHandler.isValidUrl(imageUrl)) {
        // Remove marker
        cell.setText(cellText.replace(match[0], '[No image]'));
        return;
      }

      // Fetch image
      const imageBlob = ImageHandler.fetchImage(imageUrl);

      if (!imageBlob) {
        cell.setText(cellText.replace(match[0], '[Image error]'));
        return;
      }

      // Clear cell and insert image
      cell.clear();
      const cellPara = cell.appendParagraph('');
      const inlineImage = cellPara.appendInlineImage(imageBlob);
      inlineImage.setWidth(Math.min(width, ImageHandler.MAX_WIDTH));
      inlineImage.setHeight(Math.min(height, ImageHandler.MAX_HEIGHT));
      cellPara.setAlignment(DocumentApp.HorizontalAlignment.CENTER);

      logDebug('Inserted table cell image: ' + fieldName);

    } catch (error) {
      logWarn('Failed to process image in cell: ' + error.message);
      cell.setText('[Image error]');
    }
  },

  /**
   * Captures template row structure using bulk attribute operations
   */
  captureRowTemplate: function(row) {
    const cells = [];
    const numCells = row.getNumCells();

    for (let i = 0; i < numCells; i++) {
      const cell = row.getCell(i);

      // Capture cell attributes in bulk
      const cellAttributes = cell.getAttributes();

      const cellData = {
        text: cell.getText(),
        attributes: cellAttributes,  // Store bulk attributes
        textFormatting: []
      };

      // Capture text formatting runs
      const numChildren = cell.getNumChildren();
      for (let j = 0; j < numChildren; j++) {
        const child = cell.getChild(j);
        if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
          const para = child.asParagraph();
          const paraData = {
            alignment: para.getAlignment(),
            lineSpacing: para.getLineSpacing(),
            spacingBefore: para.getSpacingBefore(),
            spacingAfter: para.getSpacingAfter(),
            textRuns: []
          };

          // Capture individual text run formatting
          const text = para.editAsText();
          const fullText = para.getText();

          if (fullText.length > 0) {
            // Sample formatting from first character (simplified approach)
            // For more precision, would need to track ranges
            paraData.textRuns.push({
              text: fullText,
              bold: text.isBold(0),
              italic: text.isItalic(0),
              underline: text.isUnderline(0),
              fontSize: text.getFontSize(0),
              fontFamily: text.getFontFamily(0),
              foregroundColor: text.getForegroundColor(0)
            });
          }

          cellData.textFormatting.push(paraData);
        }
      }

      cells.push(cellData);
    }

    return cells;
  },

  /**
   * Fills a row using bulk attribute operations
   */
  fillRowFromTemplate: function(row, templateCells, data, templateRowAttributes, isNewRow = false) {
    // Apply row-level attributes in bulk (if new row)
    if (isNewRow && templateRowAttributes) {
      try {
        row.setAttributes(templateRowAttributes);
      } catch (e) {
        logWarn('Could not apply row attributes in bulk: ' + e.message);
      }
    }

    const numCells = row.getNumCells();

    for (let i = 0; i < templateCells.length; i++) {
      let cell;

      if (isNewRow) {
        if (i < numCells) {
          cell = row.getCell(i);
        } else {
          cell = row.appendTableCell();
        }
      } else {
        cell = row.getCell(i);
      }

      const template = templateCells[i];

      // Replace merge fields in template text
      const mergedText = this.replaceFieldsInText(template.text, data);

      // Clear cell
      cell.clear();

      // Apply cell attributes in bulk
      if (template.attributes) {
        try {
          cell.setAttributes(template.attributes);
        } catch (e) {
          // Fall back to individual property setting if bulk fails
          logWarn('Bulk cell attributes failed, using fallback: ' + e.message);
        }
      }

      // Add paragraph with text and formatting
      if (template.textFormatting && template.textFormatting.length > 0) {
        const paraTemplate = template.textFormatting[0];
        const para = cell.appendParagraph(mergedText);

        // Apply paragraph-level formatting
        if (paraTemplate.alignment) {
          para.setAlignment(paraTemplate.alignment);
        }
        if (paraTemplate.lineSpacing) {
          para.setLineSpacing(paraTemplate.lineSpacing);
        }
        if (paraTemplate.spacingBefore) {
          para.setSpacingBefore(paraTemplate.spacingBefore);
        }
        if (paraTemplate.spacingAfter) {
          para.setSpacingAfter(paraTemplate.spacingAfter);
        }

        // Apply text-level formatting
        if (paraTemplate.textRuns && paraTemplate.textRuns.length > 0) {
          const textRun = paraTemplate.textRuns[0];
          const text = para.editAsText();

          if (mergedText.length > 0) {
            if (textRun.bold !== null) {
              text.setBold(textRun.bold);
            }
            if (textRun.italic !== null) {
              text.setItalic(textRun.italic);
            }
            if (textRun.underline !== null) {
              text.setUnderline(textRun.underline);
            }
            if (textRun.fontSize !== null) {
              text.setFontSize(textRun.fontSize);
            }
            if (textRun.fontFamily) {
              text.setFontFamily(textRun.fontFamily);
            }
            if (textRun.foregroundColor) {
              text.setForegroundColor(textRun.foregroundColor);
            }
          }
        }
      } else {
        cell.appendParagraph(mergedText);
      }
    }
  },

  /**
   * Gets all text from a table row
   */
  getRowText: function(row) {
    let text = '';
    const numCells = row.getNumCells();

    for (let i = 0; i < numCells; i++) {
      text += row.getCell(i).getText() + ' ';
    }

    return text;
  },

  /**
   * Removes section markers from a row
   * FIX 1: Enhanced to handle hidden characters more reliably
   */
  cleanSectionMarkers: function(row, sectionName) {
    const numCells = row.getNumCells();

    for (let i = 0; i < numCells; i++) {
      const cell = row.getCell(i);
      let text = cell.getText();

      // Support both {{#Name}} (child relationships) and {{@Name}} (data sources)
      const startMarkers = [
        '{{#' + sectionName + '}}',  // Old child relationship syntax
        '{{@' + sectionName + '}}'   // New data source syntax
      ];
      const endMarkers = [
        '{{/' + sectionName + '}}',
        '{{/@' + sectionName + '}}'  // Data source end tag
      ];

      // Remove start markers (try both syntaxes)
      for (const startMarker of startMarkers) {
        let startIndex = text.indexOf(startMarker);
        if (startIndex !== -1) {
          text = text.substring(0, startIndex) + text.substring(startIndex + startMarker.length);
        }
      }

      // Remove end markers (try both syntaxes)
      for (const endMarker of endMarkers) {
        let endIndex = text.indexOf(endMarker);
        if (endIndex !== -1) {
          text = text.substring(0, endIndex) + text.substring(endIndex + endMarker.length);
        }
      }

      // Clear and reset cell to avoid hidden character issues
      cell.clear();
      if (text.trim()) {
        cell.appendParagraph(text);
      }
    }
  },

  /**
   * Replaces fields in entire table (non-repeater)
   */
  replaceFieldsInTable: function(table, data) {
    const numRows = table.getNumRows();

    for (let r = 0; r < numRows; r++) {
      const row = table.getRow(r);
      const numCells = row.getNumCells();

      for (let c = 0; c < numCells; c++) {
        const cell = row.getCell(c);
        let text = cell.getText();
        text = this.replaceFieldsInText(text, data);
        cell.setText(text);
      }
    }
  },

  /**
   * Replaces merge fields in a text string
   * Handles conditionals, simple fields, formatted fields, and default values (v3.0)
   * NOTE: Does NOT handle IMAGE markers - those are processed separately by ImageHandler
   */
  replaceFieldsInText: function(text, data) {
    // FIRST: Process conditionals in the text using centralized ConditionalProcessor
    if (typeof ConditionalProcessor === 'undefined') {
      logError('CRITICAL: ConditionalProcessor is not defined! Did you deploy ConditionalProcessor.gs?');
    } else {
      try {
        text = ConditionalProcessor.processText(text, data);
      } catch (e) {
        logError('ConditionalProcessor.processText() failed: ' + e.message + '\n' + e.stack);
      }
    }

    // THEN: Match {{FieldName}}, {{FieldName:format}}, or {{FieldName:format ?? 'default'}}
    // Updated regex to capture everything inside {{ }}
    return text.replace(/\{\{([^}]+)\}\}/g, (match, fieldSpec) => {
      fieldSpec = fieldSpec.trim();

      // Skip IMAGE markers (processed separately by ImageHandler)
      if (fieldSpec.toUpperCase().startsWith('IMAGE')) {
        return match;
      }

      // Skip conditional markers (should have been processed already)
      if (fieldSpec.startsWith('IF ') || fieldSpec.startsWith('ELSEIF ') ||
          fieldSpec === 'ELSE' || fieldSpec.startsWith('/IF') ||
          fieldSpec.startsWith('@') || fieldSpec.startsWith('#') || fieldSpec.startsWith('/')) {
        return match;
      }

      // Parse field specification: Field:format ?? 'default' (use TemplateProcessor's parser)
      let fieldName, format, defaultValue;

      // Split by ?? for default value (v3.0 syntax)
      const parts = fieldSpec.split('??');
      const fieldPart = parts[0].trim();
      const defaultPart = parts[1] ? parts[1].trim() : null;

      // Extract format directive from field part
      const colonIndex = fieldPart.indexOf(':');
      if (colonIndex !== -1) {
        fieldName = fieldPart.substring(0, colonIndex).trim();
        format = fieldPart.substring(colonIndex + 1).trim();
      } else {
        fieldName = fieldPart;
        format = null;
      }

      // Parse default value (remove quotes)
      if (defaultPart) {
        defaultValue = defaultPart;
        if ((defaultValue.startsWith("'") && defaultValue.endsWith("'")) ||
            (defaultValue.startsWith('"') && defaultValue.endsWith('"'))) {
          defaultValue = defaultValue.slice(1, -1);
        }
      } else {
        defaultValue = null;
      }

      // Resolve field value
      let value = TemplateProcessor.resolveValue(fieldName, data);

      if (value === undefined || value === null) {
        if (defaultValue !== null) {
          return defaultValue; // Use default value
        }
        return ''; // No default, return empty string
      }

      // Pass fieldName for auto-formatting based on Salesforce field types
      return FormatUtils.formatValue(value, format, fieldName);
    });
  },

  /**
   * Resolves a field value from data (self-contained, doesn't rely on TemplateProcessor)
   * Handles dot notation for nested access
   */
  resolveFieldValue: function(fieldPath, data) {
    if (!fieldPath || !data) {
      return null;
    }

    const parts = fieldPath.trim().split('.');
    let value = data;

    for (let i = 0; i < parts.length; i++) {
      if (value === null || value === undefined) {
        return null;
      }
      if (typeof value === 'object') {
        value = value[parts[i]];
      } else {
        return null;
      }
    }

    return value;
  },

  /**
   * Parses a comparison value (inline version)
   */
  parseCompareValueInline: function(value) {
    if (!value) return value;

    value = value.trim();

    // Remove quotes
    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      return value.slice(1, -1);
    }

    // Boolean literals
    if (value.toLowerCase() === 'true') return true;
    if (value.toLowerCase() === 'false') return false;
    if (value.toLowerCase() === 'null') return null;

    // Try number
    const num = parseFloat(value);
    if (!isNaN(num)) return num;

    return value;
  },

  /**
   * Evaluates a conditional expression (kept for backward compatibility)
   * Now delegates to inline logic
   */
  evaluateCondition: function(condition, data) {
    // Use ExpressionEvaluator for consistency with TemplateProcessor
    return ExpressionEvaluator.evaluate(condition, data);
  },

  /**
   * Parses a comparison value, handling strings and booleans
   * (Kept for backward compatibility, delegates to inline version)
   */
  parseCompareValue: function(value) {
    return TableHandler.parseCompareValueInline(value);
  },

  /**
   * Processes inline repeaters (non-table sections)
   * Supports nested repeaters (grandchildren) via recursion
   * Now supports both {{#ChildRelationship}} and {{@DataSourceAlias}} syntax
   *
   * NOTE: Google Docs uses \r for paragraph breaks internally, but getText() returns \n.
   * We must handle this mismatch when using replaceText().
   *
   * @throws {Error} If inline repeater processing fails
   */
  processInlineRepeaters: function(body, childData, parentData) {
    // Use cached text read to avoid redundant API calls
    const text = DocumentCache.getBodyText(body);

    // DEBUG: Push to global DEBUG_INFO array
    if (typeof DEBUG_INFO !== 'undefined') {
      DEBUG_INFO.push('=== processInlineRepeaters ===');
      DEBUG_INFO.push('childData keys: ' + Object.keys(childData || {}).join(', '));
      DEBUG_INFO.push('parentData keys: ' + Object.keys(parentData || {}).join(', '));
      // Log sample of parent data keys for debugging
      const parentKeys = Object.keys(parentData || {});
      if (parentKeys.length > 0) {
        DEBUG_INFO.push('Sample parentData key count: ' + parentKeys.length);
      }
    }

    // Process both {{#SectionName}} and {{@Alias}} patterns
    // Patterns: Child relationships use {{#name}}, data sources use {{@name}}
    const patterns = [
      { regex: /\{\{#([^}]+)\}\}([\s\S]*?)\{\{\/\1\}\}/g, type: 'child' },
      { regex: /\{\{@([^}]+)\}\}([\s\S]*?)\{\{\/@\1\}\}/g, type: 'datasource' }
    ];

    for (const pattern of patterns) {
      let match;
      while ((match = pattern.regex.exec(text)) !== null) {
        const sectionName = match[1].trim();
        const template = match[2];
        const fullMatch = match[0];

        if (typeof DEBUG_INFO !== 'undefined') DEBUG_INFO.push('Found ' + pattern.type + ' section: ' + sectionName);

        // Check childData first (for child relationships like LineItems)
        // then parentData (for cross-object queries / data sources)
        let records = childData[sectionName];
        if (typeof DEBUG_INFO !== 'undefined') DEBUG_INFO.push('childData["' + sectionName + '"]: ' + (records ? records.length + ' records' : 'NOT FOUND'));

        if (!records || !Array.isArray(records)) {
          records = parentData && parentData[sectionName];
          if (typeof DEBUG_INFO !== 'undefined') DEBUG_INFO.push('parentData["' + sectionName + '"]: ' + (records ? records.length + ' records' : 'NOT FOUND'));
        }

        if (!records || !Array.isArray(records)) {
          if (typeof DEBUG_INFO !== 'undefined') DEBUG_INFO.push('NO RECORDS for: ' + sectionName);
          throw new Error('No data for ' + pattern.type + ' section: ' + sectionName);
        }

        if (typeof DEBUG_INFO !== 'undefined') DEBUG_INFO.push('Processing ' + records.length + ' records for: ' + sectionName);

        // Check for large datasets
        if (records.length > this.MAX_TABLE_ROWS) {
          warnings.push(`Large inline section: ${sectionName} has ${records.length} items`);
        }

        // Build replacement by repeating template for each record
        let replacement = '';
        for (let i = 0; i < records.length; i++) {
          const record = records[i];
          const rowData = { ...parentData, ...record, ROW_NUM: i + 1, ROW_INDEX: i };

          // Process nested repeaters (grandchildren) within this record
          let processedTemplate = this.processNestedRepeaters(template, record, rowData);

          // Replace simple fields
          replacement += this.replaceFieldsInText(processedTemplate, rowData);
        }

        // Debug: Log the replacement attempt
        if (typeof DEBUG_INFO !== 'undefined') {
          DEBUG_INFO.push('Template (first 100 chars): ' + template.substring(0, 100));
          DEBUG_INFO.push('Replacement (first 200 chars): ' + replacement.substring(0, 200));
        }

        // Use element-by-element approach since replaceText doesn't work across paragraphs
        const success = this.replaceMultiParagraphSection(body, sectionName, replacement);
        if (typeof DEBUG_INFO !== 'undefined') {
          DEBUG_INFO.push('replaceMultiParagraphSection result: ' + success);
        }
      }
    }
  },

  /**
   * Escapes a string for use in Google Docs replaceText() pattern.
   * Google Docs uses \r for paragraph breaks but getText() returns \n.
   */
  escapeForGoogleDocs: function(str) {
    // First escape regex special characters, then convert \n to \r
    return TemplateProcessor.escapeRegex(str).replace(/\n/g, '\\r');
  },

  /**
   * Replaces a multi-paragraph section by iterating through body elements.
   * This is more reliable than replaceText() for cross-paragraph patterns.
   * Supports both {{#name}}...{{/name}} (child) and {{@name}}...{{/@name}} (data source) syntax.
   * FIX 1: Enhanced to handle hidden characters and formatting more reliably
   *
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @param {string} sectionName - Name of the section (e.g., "RelatedRecords")
   * @param {string} replacement - The replacement text
   * @returns {boolean} True if replacement was successful
   */
  replaceMultiParagraphSection: function(body, sectionName, replacement) {
    // Try both marker syntaxes: {{#name}} (child) and {{@name}} (data source)
    const markerVariants = [
      { start: '{{#' + sectionName + '}}', end: '{{/' + sectionName + '}}' },
      { start: '{{@' + sectionName + '}}', end: '{{/@' + sectionName + '}}' }
    ];

    let startMarker = null;
    let endMarker = null;
    let startIndex = -1;
    let endIndex = -1;
    const numChildren = body.getNumChildren();

    // Find the start and end paragraph indices, trying both marker types
    for (let i = 0; i < numChildren; i++) {
      const child = body.getChild(i);
      if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
        const text = child.asParagraph().getText();

        // Try each marker variant - use more robust matching
        for (const variant of markerVariants) {
          // FIX 1: Use indexOf instead of regex to avoid hidden character issues
          if (text.indexOf(variant.start) !== -1 && startIndex === -1) {
            startIndex = i;
            startMarker = variant.start;
            endMarker = variant.end;
          }
          if (startMarker && text.indexOf(endMarker) !== -1) {
            endIndex = i;
            break;
          }
        }

        if (endIndex !== -1) break; // Found end, stop searching
      }
    }

    if (typeof DEBUG_INFO !== 'undefined') {
      DEBUG_INFO.push('Section ' + sectionName + ': startIndex=' + startIndex + ', endIndex=' + endIndex);
    }

    if (startIndex === -1 || endIndex === -1) {
      if (typeof DEBUG_INFO !== 'undefined') {
        DEBUG_INFO.push('Could not find section markers for: ' + sectionName);
      }
      return false;
    }

    // Remove elements from end to start (reverse order to maintain indices)
    for (let i = endIndex; i >= startIndex; i--) {
      body.removeChild(body.getChild(i));
    }

    // Insert replacement content at the start position
    // Split by newline and insert each line as a paragraph
    const lines = replacement.split('\n').filter(line => line.trim() !== '');

    if (typeof DEBUG_INFO !== 'undefined') {
      DEBUG_INFO.push('Inserting ' + lines.length + ' lines at index ' + startIndex);
    }

    for (let i = 0; i < lines.length; i++) {
      const para = body.insertParagraph(startIndex + i, lines[i]);
      para.setFontSize(9); // Match the template style
    }

    return true;
  },

  /**
   * Processes nested repeaters (grandchildren) within a template section
   * Called recursively to handle multiple levels of nesting
   * @param {string} template - The template text containing potential nested sections
   * @param {Object} record - The current child record (may contain grandchild arrays)
   * @param {Object} contextData - Current row data for field resolution
   * @returns {string} Processed template with nested sections expanded
   */
  processNestedRepeaters: function(template, record, contextData) {
    // Find nested section markers
    const sectionPattern = /\{\{#(\w+)\}\}([\s\S]*?)\{\{\/\1\}\}/g;
    let result = template;
    let match;

    // Reset regex lastIndex to ensure we find all matches
    sectionPattern.lastIndex = 0;

    while ((match = sectionPattern.exec(template)) !== null) {
      const nestedSectionName = match[1];
      const nestedTemplate = match[2];
      const fullMatch = match[0];

      // Look for nested child data in the current record
      const nestedRecords = record[nestedSectionName];

      if (!nestedRecords || !Array.isArray(nestedRecords)) {
        // No data for this nested section, remove it
        result = result.replace(fullMatch, '');
        continue;
      }

      // Build replacement for nested section
      let nestedReplacement = '';
      for (let j = 0; j < nestedRecords.length; j++) {
        const nestedRecord = nestedRecords[j];
        const nestedRowData = {
          ...contextData,
          ...nestedRecord,
          ROW_NUM: j + 1,
          ROW_INDEX: j,
          PARENT_ROW_NUM: contextData.ROW_NUM || 0
        };

        // Recursively process any deeper nesting (great-grandchildren)
        let processedNestedTemplate = this.processNestedRepeaters(nestedTemplate, nestedRecord, nestedRowData);

        // Replace fields in nested template
        nestedReplacement += this.replaceFieldsInText(processedNestedTemplate, nestedRowData);
      }

      // Use callback to avoid $1, $& etc. being interpreted as backreferences
      result = result.replace(fullMatch, () => nestedReplacement);
    }

    return result;
  }
};
