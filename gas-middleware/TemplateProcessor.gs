/**
 * TemplateProcessor - Handles all merge field logic and document processing
 * Version 1.0
 *
 * Supports: {{Field}}, {{Field:format}}, {{Field ?? 'default'}}, {{#Repeater}},
 * {{@DataSource}}, {{IF}}/{{ELSE}}/{{/IF}}, {{IMAGE:Field}}, {{PAGE_BREAK}}
 */
const TemplateProcessor = {

  // Merge field pattern: {{FieldName}} or {{FieldName:format}} or {{FieldName ?? 'default'}}
  FIELD_PATTERN: /\{\{([^}]+)\}\}/g,

  // Section patterns for tables/repeaters
  // {{#ChildRelationship}} for child relationships
  // {{@DataSourceAlias}} for data sources configured in Salesforce
  SECTION_START_PATTERN: /\{\{[#@]([^}]+)\}\}/g,
  SECTION_END_PATTERN: /\{\{\/[#@]?([^}]+)\}\}/g,

  // Page break pattern
  PAGE_BREAK_PATTERN: /\{\{PAGE_BREAK\}\}/gi,

  processDocument: function(docId, recordData, childData, systemVars, additionalFields, crossObjectData) {
    const timings = {};
    const warnings = [];
    const startTime = Date.now();

    // Clear caches at start of new document generation
    ImageHandler.clearCache();
    DocumentCache.clearAll();

    const doc = DocumentApp.openById(docId);
    const body = doc.getBody();
    timings.docOpen = Date.now() - startTime;

    // Initialize field types for auto-formatting (from Salesforce schema)
    if (recordData && recordData._fieldTypes) {
      FormatUtils.setFieldTypes(recordData._fieldTypes);
      // Remove _fieldTypes from merge data to avoid it appearing in the document
      delete recordData._fieldTypes;
    } else {
      FormatUtils.setFieldTypes(null);
    }

    // Merge all data sources including cross-object/data source data
    // Data source data is merged at top level so {{Alias.Field}} and {{@Alias}} resolve correctly
    const mergeData = {
      ...recordData,
      ...systemVars,
      ...additionalFields,
      ...(crossObjectData || {})
    };

    // CRITICAL: Process conditionals FIRST (before tables/repeaters)
    // Conditionals can wrap table sections and act as guards for missing data
    // Example: {{IF ShowTable}}{{#LineItems}}...{{/LineItems}}{{/IF}}
    // If we process tables first, they'll fail when LineItems is missing
    // If we process conditionals first, the false block is removed before table processing
    let stepStart = Date.now();
    const conditionalWarnings = this.processConditionals(body, mergeData);
    warnings.push(...(conditionalWarnings || []));
    timings.conditionals = Date.now() - stepStart;
    // Invalidate cache after conditional modifications
    DocumentCache.invalidateBody(body);
    DocumentCache.invalidateParagraphs();

    // Process tables/repeaters AFTER conditionals have removed false blocks
    // TableHandler now supports nested children (grandchildren)
    // Also handles data source sections ({{@DataSourceAlias}}...{{/@DataSourceAlias}})
    stepStart = Date.now();
    const tableWarnings = TableHandler.processTables(body, childData, mergeData);
    warnings.push(...(tableWarnings || []));
    timings.tables = Date.now() - stepStart;
    // Invalidate cache after table modifications
    DocumentCache.invalidateBody(body);

    // Process page breaks (before field replacements to avoid breaking markers)
    stepStart = Date.now();
    this.processPageBreaks(body);
    timings.pageBreaks = Date.now() - stepStart;

    // Process images (BEFORE field replacements to prevent text-based replacement of IMAGE markers)
    stepStart = Date.now();
    ImageHandler.processImages(body, mergeData);
    timings.images = Date.now() - stepStart;

    // Process simple field replacements (OPTIMIZED: batches unique replacements)
    stepStart = Date.now();
    this.processFields(body, mergeData);
    timings.fields = Date.now() - stepStart;
    // Final cache invalidation after field replacements
    DocumentCache.invalidateBody(body);

    // Save document
    stepStart = Date.now();
    doc.saveAndClose();
    timings.save = Date.now() - stepStart;

    timings.total = Date.now() - startTime;

    // Log performance breakdown
    logInfo(`Template processing complete in ${timings.total}ms: ` +
            `open=${timings.docOpen}ms, tables=${timings.tables}ms, ` +
            `conditionals=${timings.conditionals}ms, pageBreaks=${timings.pageBreaks}ms, ` +
            `images=${timings.images}ms, fields=${timings.fields}ms, save=${timings.save}ms`);

    // Log cache statistics
    DocumentCache.logStats();

    return { timings, warnings };
  },

  /**
   * Validates a template and returns required fields with full template text
   * @param {string} templateId - The template document ID
   * @returns {Object} Validation results with templateText included
   */
  validateTemplate: function(templateId) {
    const result = {
      isValid: true,
      fields: [],
      childRelationships: [],
      errors: [],
      warnings: [],
      templateText: ''  // Added for Salesforce-side parsing
    };

    try {
      const doc = DocumentApp.openById(templateId);
      const body = doc.getBody();

      // Read text directly (no caching needed for validation - we only read once)
      const text = body.getText();

      // Store full text for Salesforce parsing
      result.templateText = text;

      // Find all merge fields
      const fieldMatches = text.matchAll(this.FIELD_PATTERN);
      const fieldsSet = new Set();

      for (const match of fieldMatches) {
        const fieldSpec = match[1];
        const fieldName = fieldSpec.split(':')[0].trim();
        fieldsSet.add(fieldName);
      }

      result.fields = Array.from(fieldsSet);

      // Find child relationships (table sections)
      const sectionMatches = text.matchAll(this.SECTION_START_PATTERN);
      const sectionsSet = new Set();

      for (const match of sectionMatches) {
        sectionsSet.add(match[1]);
      }

      result.childRelationships = Array.from(sectionsSet);

      // Check for unclosed sections
      for (const section of sectionsSet) {
        const endPattern = new RegExp(`\\{\\{\\/${section}\\}\\}`);
        if (!endPattern.test(text)) {
          result.errors.push(`Unclosed section: {{#${section}}}`);
          result.isValid = false;
        }
      }

    } catch (error) {
      result.isValid = false;
      result.errors.push(`Failed to open template: ${error.message}`);
    }

    return result;
  },

  /**
   * Processes page breaks in the document
   * Finds {{PAGE_BREAK}} markers and replaces them with actual page break elements
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @throws {Error} If page break processing fails
   */
  processPageBreaks: function(body) {
    // Find all {{PAGE_BREAK}} markers by scanning through paragraphs
    const numChildren = body.getNumChildren();
    const pageBreakPositions = [];

    // First pass: Find all page break markers and their positions
    for (let i = 0; i < numChildren; i++) {
      const child = body.getChild(i);

      if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
        const para = child.asParagraph();
        const text = para.getText();

        // Check if this paragraph contains a page break marker
        if (this.PAGE_BREAK_PATTERN.test(text)) {
          pageBreakPositions.push({
            index: i,
            paragraph: para,
            text: text
          });
        }
      }
    }

    // Second pass: Replace markers with actual page breaks (in reverse order to maintain indices)
    for (let i = pageBreakPositions.length - 1; i >= 0; i--) {
      const pos = pageBreakPositions[i];
      const para = pos.paragraph;
      const text = pos.text;

      // Check if paragraph contains ONLY the page break marker (possibly with whitespace)
      const cleanText = text.trim();
      const isOnlyPageBreak = /^\{\{PAGE_BREAK\}\}$/i.test(cleanText);

      if (isOnlyPageBreak) {
        // Replace entire paragraph with a page break
        const paraIndex = body.getChildIndex(para);
        para.removeFromParent();
        body.insertPageBreak(paraIndex);
      } else {
        // Page break marker is mixed with other text
        // Replace marker with placeholder, then insert page break after paragraph
        const beforeText = text.substring(0, text.search(this.PAGE_BREAK_PATTERN));
        const afterMatch = text.match(this.PAGE_BREAK_PATTERN);
        const markerEnd = text.search(this.PAGE_BREAK_PATTERN) + afterMatch[0].length;
        const afterText = text.substring(markerEnd);

        if (beforeText || afterText) {
          // Split the content around the page break
          const paraIndex = body.getChildIndex(para);

          // Set paragraph to before text
          if (beforeText) {
            para.setText(beforeText);
          } else {
            para.removeFromParent();
          }

          // Insert page break
          const pageBreakIndex = beforeText ? paraIndex + 1 : paraIndex;
          body.insertPageBreak(pageBreakIndex);

          // Insert after text as new paragraph
          if (afterText) {
            body.insertParagraph(pageBreakIndex + 1, afterText);
          }
        } else {
          // Just the marker, replace with page break
          const paraIndex = body.getChildIndex(para);
          para.removeFromParent();
          body.insertPageBreak(paraIndex);
        }
      }
    }

    if (pageBreakPositions.length > 0) {
      logInfo('Inserted ' + pageBreakPositions.length + ' page break(s)');
    }
  },

  /**
   * Processes simple field replacements in the body
   * OPTIMIZED: Uses Google Docs Advanced API batchUpdate for massive performance gains
   * Falls back to traditional replaceText() if batch API fails
   *
   * Supports:
   * - {{Field}}
   * - {{Field:format}}
   * - {{Field ?? 'default'}}
   * - {{Field:format ?? 'default'}}
   *
   * @throws {Error} If field not found and no default provided
   */
  processFields: function(body, mergeData) {
    // Use cached text read instead of direct API call
    const text = DocumentCache.getBodyText(body);

    // Collect unique replacements (same field may appear multiple times)
    const replacementMap = new Map(); // fullMatch -> replacement value

    // Find all field references
    const matches = text.matchAll(this.FIELD_PATTERN);

    for (const match of matches) {
      const fullMatch = match[0];
      const fieldSpec = match[1];

      // Skip if already processed this exact match
      if (replacementMap.has(fullMatch)) {
        continue;
      }

      // Skip PAGE_BREAK (already processed)
      if (fieldSpec.trim().toUpperCase() === 'PAGE_BREAK') {
        continue;
      }

      // Skip IMAGE markers (processed by ImageHandler)
      if (fieldSpec.trim().toUpperCase().startsWith('IMAGE')) {
        continue;
      }

      // Skip conditional/section markers
      if (fieldSpec.trim().match(/^(IF\s|ELSEIF\s|ELSE|\/IF|#|@|\/)/i)) {
        continue;
      }

      // Parse field specification: Field:format ?? 'default'
      const parsed = this.parseFieldSpec(fieldSpec);

      // Get value
      let value = this.resolveValue(parsed.fieldName, mergeData);

      if (value === undefined || value === null) {
        if (parsed.defaultValue !== null) {
          // Use default value
          value = parsed.defaultValue;
        } else {
          // No default - FAIL FAST
          throw new Error('Field not found: ' + parsed.fieldName + ' (use {{' + parsed.fieldName + ' ?? \'default\'}} to provide a default value)');
        }
      } else {
        // Apply formatting (with auto-format from field types if no explicit format)
        value = FormatUtils.formatValue(value, parsed.format, parsed.fieldName);
      }

      replacementMap.set(fullMatch, value.toString());
    }

    // Apply replacements using batch API (MAJOR PERFORMANCE IMPROVEMENT)
    this.applyFieldReplacementsBatch(body, replacementMap);
  },

  /**
   * Applies field replacements using Google Docs Advanced API batchUpdate
   * This reduces N API calls to 1 single batch call
   *
   * PERFORMANCE: 50 fields = 1 API call instead of 50 API calls
   *
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @param {Map} replacementMap - Map of patterns to replacement values
   */
  applyFieldReplacementsBatch: function(body, replacementMap) {
    if (replacementMap.size === 0) {
      return;
    }

    let docId;
    try {
      docId = body.getParent().getId();
    } catch (e) {
      // If we can't get document ID, skip batch API and use fallback
      logWarn('Cannot get document ID for batch API, using fallback: ' + e.message);
      docId = null;
    }

    // If we couldn't get docId, use fallback directly
    if (!docId) {
      const fallbackStartTime = Date.now();
      for (const [fullMatch, value] of replacementMap) {
        body.replaceText(this.escapeRegex(fullMatch), this.escapeReplacement(value));
      }
      const fallbackTime = Date.now() - fallbackStartTime;
      logInfo(`Replaced ${replacementMap.size} field(s) in ${fallbackTime}ms (${replacementMap.size} API calls)`);
      return;
    }

    const batchStartTime = Date.now();

    try {
      // Build batch requests for all replacements
      const requests = [];

      for (const [pattern, value] of replacementMap) {
        requests.push({
          replaceAllText: {
            containsText: {
              text: pattern,        // Literal text match (not regex)
              matchCase: true       // Case-sensitive matching
            },
            replaceText: value || '' // Handle empty values
          }
        });
      }

      // SINGLE BATCH CALL - This is the key optimization!
      logDebug(`Executing batch replacement of ${requests.length} fields...`);
      Docs.Documents.batchUpdate({ requests: requests }, docId);

      const batchTime = Date.now() - batchStartTime;
      logInfo(`Batch replaced ${replacementMap.size} unique field(s) in ${batchTime}ms (1 API call)`);

    } catch (batchError) {
      // FALLBACK: If batch API fails, use traditional replaceText() method
      logWarn('Batch API failed, falling back to replaceText(): ' + batchError.message);

      const fallbackStartTime = Date.now();
      for (const [fullMatch, value] of replacementMap) {
        body.replaceText(this.escapeRegex(fullMatch), this.escapeReplacement(value));
      }

      const fallbackTime = Date.now() - fallbackStartTime;
      logInfo(`Fallback: Replaced ${replacementMap.size} field(s) in ${fallbackTime}ms (${replacementMap.size} API calls)`);
    }
  },

  /**
   * Parses a field specification into components
   * Examples:
   * - "Field" -> {fieldName: "Field", format: null, defaultValue: null}
   * - "Field:currency" -> {fieldName: "Field", format: "currency", defaultValue: null}
   * - "Field ?? 'default'" -> {fieldName: "Field", format: null, defaultValue: "default"}
   * - "Field:currency ?? '$0.00'" -> {fieldName: "Field", format: "currency", defaultValue: "$0.00"}
   *
   * @param {string} fieldSpec - The field specification
   * @returns {Object} Parsed components
   */
  parseFieldSpec: function(fieldSpec) {
    // Split by ?? for default value
    const parts = fieldSpec.split('??');
    const fieldPart = parts[0].trim();
    const defaultPart = parts[1] ? parts[1].trim() : null;

    // Parse field name and format from field part
    const colonIndex = fieldPart.indexOf(':');
    let fieldName, format;

    if (colonIndex !== -1) {
      fieldName = fieldPart.substring(0, colonIndex).trim();
      format = fieldPart.substring(colonIndex + 1).trim();
    } else {
      fieldName = fieldPart;
      format = null;
    }

    // Parse default value (remove quotes if present)
    let defaultValue = null;
    if (defaultPart) {
      defaultValue = defaultPart;
      // Remove surrounding quotes
      if ((defaultValue.startsWith("'") && defaultValue.endsWith("'")) ||
          (defaultValue.startsWith('"') && defaultValue.endsWith('"'))) {
        defaultValue = defaultValue.slice(1, -1);
      }
    }

    return {
      fieldName: fieldName,
      format: format,
      defaultValue: defaultValue
    };
  },

  /**
   * Processes conditional sections (Block-Level and Inline)
   *
   * STRATEGY:
   * 1. First, handle Block-Level conditionals (spanning multiple paragraphs/tables).
   *    This allows removing entire tables if a condition is false.
   * 2. Then, handle Inline conditionals (inside specific paragraphs/cells).
   *
   * Block-Level conditionals must have tags in their own paragraphs:
   *   {{IF ShowTable}}
   *   [content including tables]
   *   {{/IF}}
   *
   * @throws {Error} If conditional processing fails
   */
  processConditionals: function(body, mergeData) {
    let totalProcessed = 0;
    const warnings = [];
    logInfo('Starting conditional processing...');

    // PHASE 1: Block-Level Processing (Spanning paragraphs/tables)
    // Uses element-by-element scanning to find blocks and delete ranges
    totalProcessed += this.processBlockLogic(body, mergeData);
    logInfo(`Processed ${totalProcessed} block-level conditional(s)`);

    // PHASE 2: Element-Level Processing (Inside paragraphs)
    // Cleans up any remaining inline logic and handles nested structures
    // Skip tables because TableHandler will handle cell logic later
    const inlineCount = this.processConditionalsInElement(body, mergeData, true);
    totalProcessed += inlineCount;
    logInfo(`Processed ${inlineCount} inline conditional(s)`);

    logInfo(`Total conditionals processed: ${totalProcessed}`);
    return warnings;
  },

  /**
   * Handles conditionals that span multiple paragraphs or elements (like tables)
   *
   * Block-Level conditionals must use strict paragraph-only tags:
   *   {{IF condition}}      <- Must be alone in paragraph
   *   [content]
   *   {{/IF}}               <- Must be alone in paragraph
   *
   * This simplified approach reliably handles the critical "wrap a table" use case.
   * Inline conditionals (within text) are handled by processConditionalsInElement.
   *
   * @param {GoogleAppsScript.Document.Body} body - Document body
   * @param {Object} data - Data for conditional evaluation
   * @returns {number} Number of block-level conditionals processed
   * @throws {Error} If conditional evaluation fails
   */
  processBlockLogic: function(body, data) {
    let count = 0;
    let i = 0;

    // Scan paragraphs to find OPENING {{IF}} tags (in their own paragraphs)
    while (i < body.getNumChildren()) {
      const child = body.getChild(i);

      if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
        const text = child.asParagraph().getText();

        // Found Start of Block? (Strict: tag must be alone in paragraph)
        // Use [^}]+ to prevent matching beyond the first }}
        const startMatch = text.match(/^\{\{IF\s+([^}]+)\}\}\s*$/);
        if (startMatch) {
          const condition = startMatch[1];
          const startIndex = i;

          // Search forward for End of Block
          let endIndex = -1;
          let depth = 1;

          for (let j = i + 1; j < body.getNumChildren(); j++) {
            const nextChild = body.getChild(j);
            if (nextChild.getType() === DocumentApp.ElementType.PARAGRAPH) {
              const nextText = nextChild.asParagraph().getText();

              // Track nested {{IF}} blocks
              if (nextText.match(/^\{\{IF\s+/)) {
                depth++;
              }

              // Track closing {{/IF}} blocks
              if (nextText.match(/^\{\{\/IF\}\}\s*$/)) {
                depth--;

                if (depth === 0) {
                  endIndex = j;
                  break;
                }
              }
            }
          }

          if (endIndex !== -1) {
            // Evaluate Condition
            let isTrue = false;
            try {
              isTrue = ExpressionEvaluator.evaluate(condition, data);
            } catch (e) {
              throw new Error('Conditional evaluation failed for "' + condition + '": ' + e.message);
            }

            if (isTrue) {
              // True: Remove markers, keep content
              body.getChild(endIndex).removeFromParent(); // Remove {{/IF}}
              body.getChild(startIndex).removeFromParent(); // Remove {{IF}}
              // Content remains between. Don't increment i (we removed current element)
              count++;
              continue;
            } else {
              // False: Remove EVERYTHING between start and end (inclusive)
              for (let k = endIndex; k >= startIndex; k--) {
                body.getChild(k).removeFromParent();
              }
              // i is now pointing to element AFTER the deleted block
              count++;
              continue;
            }
          } else {
            // No matching {{/IF}} found - this is an error
            throw new Error('Unclosed {{IF}} block starting with: ' + condition);
          }
        }
      }

      i++;
    }

    return count;
  },

  /**
   * Recursively processes conditionals in a document element
   * @param {GoogleAppsScript.Document.Element} element - Element to process
   * @param {Object} mergeData - Merge data for conditional evaluation
   * @param {boolean} skipTables - If true, skip processing table elements (already processed by TableHandler)
   * @returns {number} Number of conditionals processed
   * @throws {Error} If conditional processing fails
   */
  processConditionalsInElement: function(element, mergeData, skipTables) {
    let processed = 0;
    skipTables = skipTables || false;

    const type = element.getType();

    // Handle different element types
    if (type === DocumentApp.ElementType.BODY_SECTION) {
      const body = element.asBody();
      const numChildren = body.getNumChildren();
      for (let i = 0; i < numChildren; i++) {
        processed += this.processConditionalsInElement(body.getChild(i), mergeData, skipTables);
      }
    } else if (type === DocumentApp.ElementType.PARAGRAPH) {
      processed += this.processConditionalsInParagraph(element.asParagraph(), mergeData);
    } else if (type === DocumentApp.ElementType.TABLE) {
      // SKIP tables if they were already processed by TableHandler
      if (skipTables) {
        logInfo('Skipping table element (already processed by TableHandler)');
        return 0;
      }

      const table = element.asTable();
      const numRows = table.getNumRows();
      for (let i = 0; i < numRows; i++) {
        const row = table.getRow(i);
        const numCells = row.getNumCells();
        for (let j = 0; j < numCells; j++) {
          const cell = row.getCell(j);
          const numChildren = cell.getNumChildren();
          for (let k = 0; k < numChildren; k++) {
            processed += this.processConditionalsInElement(cell.getChild(k), mergeData, skipTables);
          }
        }
      }
    } else if (type === DocumentApp.ElementType.LIST_ITEM) {
      processed += this.processConditionalsInParagraph(element.asListItem(), mergeData);
    }
    // Note: INLINE_IMAGE, HORIZONTAL_RULE, etc. don't contain text

    return processed;
  },

  /**
   * Processes conditionals within a single paragraph or list item
   * @param {GoogleAppsScript.Document.Paragraph|GoogleAppsScript.Document.ListItem} para - Paragraph to process
   * @param {Object} mergeData - Merge data for conditional evaluation
   * @returns {number} Number of conditionals processed
   * @throws {Error} If conditional processing fails
   */
  processConditionalsInParagraph: function(para, mergeData) {
    // Use centralized ConditionalProcessor (throws on error)
    const processed = ConditionalProcessor.processParagraph(para, mergeData);
    return processed ? 1 : 0;
  },

  /**
   * Resolves a field value from merged data
   * Uses nested object traversal matching Salesforce data model:
   * - Template: {{Account.Name}}
   * - Data: { Account: { Name: "Acme Corp" } }
   *
   * This also works for data source aliases:
   * - Template: {{OpenCases.Subject}}
   * - Data: { OpenCases: { Subject: "My Case" } }
   */
  resolveValue: function(fieldName, data) {
    if (!fieldName || !data) return null;

    // Handle dot notation by traversing nested objects
    const parts = fieldName.split('.');
    let value = data;

    for (const part of parts) {
      if (value === null || value === undefined) return null;

      if (typeof value === 'object') {
        value = value[part];
      } else {
        return null;
      }
    }

    return value;
  },

  /**
   * Evaluates a conditional expression using ExpressionEvaluator
   * Supports AND, OR, NOT operators and complex expressions
   */
  evaluateCondition: function(condition, data) {
    // Use ExpressionEvaluator for all conditional logic
    return ExpressionEvaluator.evaluate(condition, data);
  },

  /**
   * Parses a comparison value (handles quotes)
   */
  parseCompareValue: function(value) {
    value = value.trim();
    // Remove quotes if present
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.slice(1, -1);
    }
    // Try to parse as number
    if (!isNaN(value)) {
      return Number(value);
    }
    return value;
  },

  /**
   * Escapes special regex characters in search pattern
   */
  escapeRegex: function(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  },

  /**
   * Escapes special replacement characters to prevent $1, $2, etc. from being
   * interpreted as backreferences in replaceText()
   *
   * Google Apps Script's replaceText uses JavaScript's replace() under the hood,
   * which interprets $& (entire match), $1-$9 (capture groups), $` (before match),
   * $' (after match) as special sequences.
   *
   * @param {string} str - The replacement string
   * @returns {string} Escaped replacement string safe for replaceText()
   */
  escapeReplacement: function(str) {
    if (str === null || str === undefined) return '';
    // Escape $ by doubling it ($$) to make it literal
    return String(str).replace(/\$/g, '$$$$');
  }
};
