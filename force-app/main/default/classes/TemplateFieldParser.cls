/**
 * @description Parser for extracting merge fields from Google Doc templates.
 * Supports the hybrid nomenclature:
 * - Main object fields: {{QuoteNumber}}
 * - Parent relationships: {{Account.Name}}, {{Account.Parent.Name}} (multi-level)
 * - Child relationships: {{#QuoteLineItems}}...{{/QuoteLineItems}}
 * - Data sources: {{@Alias.Field}} or {{@Alias}}...{{/@Alias}} (new syntax)
 * - Nested children: {{#QuoteLineItems}}{{#ChildRelation}}...{{/ChildRelation}}{{/QuoteLineItems}}
 * - System variables: {{TODAY}}, {{CURRENT_USER.Name}}
 * - Format directives: {{Amount:currency}}, {{Date:date}}
 * - Default values: {{Field ?? 'default'}}, {{Field:currency ?? '$0.00'}} (v3.0)
 * - Conditionals: {{IF condition}}...{{ELSEIF condition}}...{{ELSE}}...{{/IF}} (v3.0)
 * - Special markers: {{PAGE_BREAK}}, {{IMAGE:FieldName:widthxheight}}
 *
 * Version History:
 * - v1: Initial implementation
 * - v2: Added data source disambiguation with @ prefix
 * - v3: Added regex safety checks and nesting depth validation
 * - v4: Added default value syntax (??), updated conditionals, ELSEIF support
 *
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class TemplateFieldParser {

    // Current schema version for cached JSON
    private static final Integer SCHEMA_VERSION = 4;

    /**
     * @description Exception for template parsing errors
     */
    public class TemplateParserException extends Exception {}
    
    /**
     * @description Types of fields found in templates
     */
    public enum FieldType {
        MAIN_OBJECT,          // {{QuoteNumber}}
        PARENT_RELATIONSHIP,  // {{Account.Name}}, {{Account.Parent.Name}}
        CHILD_RELATIONSHIP,   // {{#QuoteLineItems}}
        SYSTEM_VARIABLE,      // {{TODAY}}, {{CURRENT_USER.Name}}
        DATA_SOURCE           // Fields from TemplateDataSource__c (e.g., {{OpenCases.Subject}})
    }
    
    /**
     * @description Represents a parsed field from the template
     */
    public class ParsedField {
        public FieldType fieldType { get; set; }
        public String fieldName { get; set; }           // The field API name
        public String relationshipPath { get; set; }    // Full path like Account.Name or Account.Parent.Name
        public String formatDirective { get; set; }     // currency, date, etc.
        public String defaultValue { get; set; }        // Default value from ?? operator (v3.0)
        public Integer depth { get; set; }              // Relationship depth (0, 1, 2+)
        public List<ParsedField> childFields { get; set; } // For child relationships
        public List<ParsedField> nestedChildren { get; set; } // For grandchildren (nested child relationships)
        public String parentRelationshipName { get; set; } // For nested children, tracks parent context
        public String dataSourceAlias { get; set; }     // For data source references

        public ParsedField() {
            this.depth = 0;
            this.childFields = new List<ParsedField>();
            this.nestedChildren = new List<ParsedField>();
        }
        
        /**
         * @description Returns the SOQL field path for this field
         */
        public String toSOQLPath() {
            if (fieldType == TemplateFieldParser.FieldType.SYSTEM_VARIABLE ||
                fieldType == TemplateFieldParser.FieldType.DATA_SOURCE) {
                return null; // System vars and data source refs don't need main query SOQL
            }
            if (String.isNotBlank(relationshipPath)) {
                return relationshipPath;
            }
            return fieldName;
        }
        
        /**
         * @description Checks if this child relationship has nested children
         */
        public Boolean hasNestedChildren() {
            return nestedChildren != null && !nestedChildren.isEmpty();
        }
    }
    
    /**
     * @description Result of parsing a template
     */
    public class ParseResult {
        public List<ParsedField> mainObjectFields { get; set; }
        public List<ParsedField> parentRelationshipFields { get; set; }
        public List<ParsedField> childRelationships { get; set; }
        public List<ParsedField> systemVariables { get; set; }
        public Set<String> dataSourceAliasesReferenced { get; set; } // Aliases used in template
        public List<String> errors { get; set; }
        public List<String> warnings { get; set; }
        
        public ParseResult() {
            this.mainObjectFields = new List<ParsedField>();
            this.parentRelationshipFields = new List<ParsedField>();
            this.childRelationships = new List<ParsedField>();
            this.systemVariables = new List<ParsedField>();
            this.dataSourceAliasesReferenced = new Set<String>();
            this.errors = new List<String>();
            this.warnings = new List<String>();
        }
        
        /**
         * @description Converts the parse result to JSON for storage
         * Includes schema version to detect outdated cached data
         */
        public String toJSON() {
            Map<String, Object> jsonMap = new Map<String, Object>{
                'schemaVersion' => SCHEMA_VERSION,
                'mainObjectFields' => convertFieldsToMap(mainObjectFields),
                'parentRelationshipFields' => convertFieldsToMap(parentRelationshipFields),
                'childRelationships' => convertChildRelationshipsToMap(childRelationships),
                'systemVariables' => convertFieldsToMap(systemVariables),
                'dataSourceAliasesReferenced' => new List<String>(dataSourceAliasesReferenced),
                'errors' => errors,
                'warnings' => warnings,
                'parsedAt' => DateTime.now().format()
            };
            return JSON.serializePretty(jsonMap);
        }
        
        private List<Map<String, Object>> convertFieldsToMap(List<ParsedField> fields) {
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (ParsedField field : fields) {
                Map<String, Object> fieldMap = new Map<String, Object>{
                    'fieldName' => field.fieldName,
                    'relationshipPath' => field.relationshipPath,
                    'formatDirective' => field.formatDirective,
                    'defaultValue' => field.defaultValue,
                    'depth' => field.depth,
                    'fieldType' => field.fieldType != null ? field.fieldType.name() : 'MAIN_OBJECT'
                };
                if (String.isNotBlank(field.dataSourceAlias)) {
                    fieldMap.put('dataSourceAlias', field.dataSourceAlias);
                }
                result.add(fieldMap);
            }
            return result;
        }
        
        private List<Map<String, Object>> convertChildRelationshipsToMap(List<ParsedField> relationships) {
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (ParsedField rel : relationships) {
                Map<String, Object> relMap = new Map<String, Object>{
                    'relationshipName' => rel.fieldName,
                    'childFields' => convertFieldsToMap(rel.childFields)
                };
                // Include nested children (grandchildren) if present
                if (rel.hasNestedChildren()) {
                    relMap.put('nestedChildren', convertChildRelationshipsToMap(rel.nestedChildren));
                }
                result.add(relMap);
            }
            return result;
        }
    }
    
    private static List<ParsedField> reconstructFields(List<Object> fieldList) {
        List<ParsedField> result = new List<ParsedField>();
        for (Object obj : fieldList) {
            Map<String, Object> fieldMap = (Map<String, Object>) obj;
            ParsedField field = new ParsedField();
            field.fieldName = (String) fieldMap.get('fieldName');
            field.relationshipPath = (String) fieldMap.get('relationshipPath');
            field.formatDirective = (String) fieldMap.get('formatDirective');
            field.defaultValue = (String) fieldMap.get('defaultValue');
            field.depth = fieldMap.containsKey('depth') ? Integer.valueOf(fieldMap.get('depth')) : 0;
            field.dataSourceAlias = (String) fieldMap.get('dataSourceAlias');

            // Restore field type from stored value if available
            if (fieldMap.containsKey('fieldType')) {
                String fieldTypeStr = (String) fieldMap.get('fieldType');
                if (fieldTypeStr == 'MAIN_OBJECT') {
                    field.fieldType = FieldType.MAIN_OBJECT;
                } else if (fieldTypeStr == 'PARENT_RELATIONSHIP') {
                    field.fieldType = FieldType.PARENT_RELATIONSHIP;
                } else if (fieldTypeStr == 'SYSTEM_VARIABLE') {
                    field.fieldType = FieldType.SYSTEM_VARIABLE;
                } else if (fieldTypeStr == 'CHILD_RELATIONSHIP') {
                    field.fieldType = FieldType.CHILD_RELATIONSHIP;
                } else if (fieldTypeStr == 'DATA_SOURCE') {
                    field.fieldType = FieldType.DATA_SOURCE;
                } else {
                    field.fieldType = FieldType.MAIN_OBJECT;
                }
            } else {
                // Fallback: Determine field type from structure
                if (field.depth == 0 && String.isBlank(field.relationshipPath)) {
                    field.fieldType = FieldType.MAIN_OBJECT;
                } else if (field.depth > 0 || String.isNotBlank(field.relationshipPath)) {
                    field.fieldType = FieldType.PARENT_RELATIONSHIP;
                } else {
                    field.fieldType = FieldType.MAIN_OBJECT;
                }
            }

            result.add(field);
        }
        return result;
    }
    
    private static List<ParsedField> reconstructChildRelationships(List<Object> relList) {
        List<ParsedField> result = new List<ParsedField>();
        for (Object obj : relList) {
            Map<String, Object> relMap = (Map<String, Object>) obj;
            ParsedField rel = new ParsedField();
            rel.fieldName = (String) relMap.get('relationshipName');
            rel.fieldType = FieldType.CHILD_RELATIONSHIP;
            if (relMap.containsKey('childFields')) {
                rel.childFields = reconstructFields((List<Object>) relMap.get('childFields'));
            }
            // Reconstruct nested children (grandchildren) recursively
            if (relMap.containsKey('nestedChildren')) {
                rel.nestedChildren = reconstructChildRelationships((List<Object>) relMap.get('nestedChildren'));
            }
            result.add(rel);
        }
        return result;
    }
    
    /**
     * @description Creates ParseResult from stored JSON
     * Validates schema version and throws exception if outdated
     * @param jsonString The JSON string to deserialize
     * @return ParseResult The reconstructed parse result
     */
    public static ParseResult fromJSON(String jsonString) {
        ParseResult result = new ParseResult();

        if (String.isBlank(jsonString)) {
            return result;
        }

        try {
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);

            // Check schema version - FAIL HARD on version mismatch
            if (!jsonMap.containsKey('schemaVersion')) {
                throw new TemplateParserException('Cached template data has no schema version. ' +
                    'This template was created with an older version of the framework. ' +
                    'Re-validate the template to continue.');
            }

            Integer version = Integer.valueOf(jsonMap.get('schemaVersion'));

            if (version != SCHEMA_VERSION) {
                throw new TemplateParserException('Cached template data version mismatch (found ' + version + ', expected ' + SCHEMA_VERSION + '). ' +
                    'Re-validate the template before use. Do not use templates validated with different framework versions.');
            }

            if (jsonMap.containsKey('mainObjectFields')) {
                result.mainObjectFields = reconstructFields((List<Object>) jsonMap.get('mainObjectFields'));
            }
            if (jsonMap.containsKey('parentRelationshipFields')) {
                result.parentRelationshipFields = reconstructFields((List<Object>) jsonMap.get('parentRelationshipFields'));
            }
            if (jsonMap.containsKey('childRelationships')) {
                result.childRelationships = reconstructChildRelationships((List<Object>) jsonMap.get('childRelationships'));
            }
            if (jsonMap.containsKey('systemVariables')) {
                result.systemVariables = reconstructFields((List<Object>) jsonMap.get('systemVariables'));
            }
            if (jsonMap.containsKey('dataSourceAliasesReferenced')) {
                List<Object> aliases = (List<Object>) jsonMap.get('dataSourceAliasesReferenced');
                for (Object alias : aliases) {
                    result.dataSourceAliasesReferenced.add(String.valueOf(alias));
                }
            }

        } catch (Exception e) {
            result.errors.add('Failed to parse stored JSON: ' + e.getMessage());
        }

        return result;
    }
    
    /**
     * @description Parses a template text and extracts all merge fields
     * @param templateText The full text content from the Google Doc
     * @param mainObjectName The API name of the main object (e.g., Quote)
     * @return ParseResult containing all parsed fields and any errors/warnings
     */
    public static ParseResult parseTemplate(String templateText, String mainObjectName) {
        return parseTemplateWithDataSources(templateText, mainObjectName, new Set<String>());
    }
    
    /**
     * @description Parses a template text with known data source aliases
     * @param templateText The full text content from the Google Doc
     * @param mainObjectName The API name of the main object (e.g., Quote)
     * @param knownDataSourceAliases Set of aliases from TemplateDataSource__c records
     * @return ParseResult containing all parsed fields and any errors/warnings
     */
    public static ParseResult parseTemplateWithDataSources(
        String templateText,
        String mainObjectName,
        Set<String> knownDataSourceAliases
    ) {
        ParseResult result = new ParseResult();

        if (String.isBlank(templateText)) {
            result.errors.add('Template text is empty');
            return result;
        }

        if (String.isBlank(mainObjectName)) {
            result.errors.add('Main object name is required');
            return result;
        }

        // SAFETY CHECKS: Prevent regex timeouts and pathological cases

        // Check 1: Template size limit (1MB = 1,048,576 characters)
        if (templateText.length() > 1048576) {
            result.errors.add('Template too large: ' + templateText.length() + ' characters. Maximum 1MB (1,048,576 characters).');
            return result;
        }

        // Check 2: Field count limit
        Integer fieldCount = countOccurrences(templateText, '{{');
        if (fieldCount > 2000) {
            result.errors.add('Template has too many merge fields: ' + fieldCount + '. Maximum 2000 fields.');
            return result;
        }

        // Check 3: Detect unbalanced braces (potential parsing errors)
        Integer openBraces = countOccurrences(templateText, '{{');
        Integer closeBraces = countOccurrences(templateText, '}}');
        if (openBraces != closeBraces) {
            result.warnings.add('Unbalanced braces detected: ' + openBraces + ' opening {{ but ' + closeBraces + ' closing }}. This may cause parsing errors.');
        }

        // Check 4: Validate section tag nesting depth
        Integer maxNestingDepth = calculateMaxNestingDepth(templateText);
        if (maxNestingDepth > 5) {
            result.errors.add('Section nesting too deep: ' + maxNestingDepth + ' levels. Maximum 5 levels to prevent performance issues.');
            return result;
        } else if (maxNestingDepth > 3) {
            result.warnings.add('Section nesting depth is ' + maxNestingDepth + ' levels. Consider simplifying template structure for better performance.');
        }

        // First, identify all child section content to exclude from main parsing
        Set<String> childSectionContent = extractChildSectionContent(templateText);
        
        // Remove child sections from template text for main field parsing
        String mainTemplateText = removeChildSections(templateText);
        
        // Track unique fields to avoid duplicates
        Set<String> processedFields = new Set<String>();
        
        // Pattern for simple fields: {{FieldName}} or {{Field:format}} or {{@Alias.Field}}
        // Updated to exclude @ prefix to avoid parsing data source markers as simple fields
        Pattern simplePattern = Pattern.compile('\\{\\{([^#/@}]+)\\}\\}');
        Matcher m = simplePattern.matcher(mainTemplateText);

        while (m.find()) {
            String fieldExpr = m.group(1).trim();

            // Skip conditionals (v3.0 syntax)
            if (fieldExpr.startsWithIgnoreCase('IF ') ||
                fieldExpr.startsWithIgnoreCase('ELSEIF ') ||
                fieldExpr.equalsIgnoreCase('ELSE') ||
                fieldExpr.startsWithIgnoreCase('/IF')) {
                continue;
            }

            // Skip special GAS-side markers
            if (isSpecialMarker(fieldExpr)) {
                continue;
            }

            // Skip if already processed
            if (processedFields.contains(fieldExpr)) {
                continue;
            }
            processedFields.add(fieldExpr);

            ParsedField parsed = parseFieldExpression(fieldExpr, mainObjectName, knownDataSourceAliases, result);

            // Add to appropriate list
            if (parsed.fieldType == FieldType.MAIN_OBJECT) {
                result.mainObjectFields.add(parsed);
            } else if (parsed.fieldType == FieldType.PARENT_RELATIONSHIP) {
                result.parentRelationshipFields.add(parsed);
            } else if (parsed.fieldType == FieldType.SYSTEM_VARIABLE) {
                result.systemVariables.add(parsed);
            } else if (parsed.fieldType == FieldType.DATA_SOURCE) {
                // Track that this data source alias is used
                if (String.isNotBlank(parsed.dataSourceAlias)) {
                    result.dataSourceAliasesReferenced.add(parsed.dataSourceAlias);
                }
            }
        }

        // Parse data source field references with @ prefix: {{@Alias.Field}}
        parseDataSourceFieldReferences(mainTemplateText, knownDataSourceAliases, result, processedFields);
        
        // Parse IMAGE markers to extract field names
        parseImageMarkers(mainTemplateText, mainObjectName, knownDataSourceAliases, result, processedFields);
        
        // Parse child relationships with nested children support
        result.childRelationships = parseChildRelationshipsWithNesting(templateText, mainObjectName, knownDataSourceAliases, result);
        
        // Validate child relationship closures
        validateChildRelationships(templateText, result);
        
        return result;
    }
    
    /**
     * @description Parses IMAGE markers and extracts field names that need to be queried
     */
    private static void parseImageMarkers(
        String templateText,
        String mainObjectName,
        Set<String> knownDataSourceAliases,
        ParseResult result,
        Set<String> processedFields
    ) {
        Pattern imagePattern = Pattern.compile('(?i)\\{\\{IMAGE:([^:}]+)(?::\\d+x\\d+)?\\}\\}');
        Matcher m = imagePattern.matcher(templateText);

        while (m.find()) {
            String fieldPath = m.group(1).trim();

            if (processedFields.contains('IMAGE:' + fieldPath)) {
                continue;
            }
            processedFields.add('IMAGE:' + fieldPath);

            ParsedField parsed = parseFieldExpression(fieldPath, mainObjectName, knownDataSourceAliases, result);

            if (parsed.fieldType == FieldType.MAIN_OBJECT) {
                result.mainObjectFields.add(parsed);
            } else if (parsed.fieldType == FieldType.PARENT_RELATIONSHIP) {
                result.parentRelationshipFields.add(parsed);
            }
        }
    }

    /**
     * @description Parses data source field references with @ prefix: {{@Alias.Field}}
     * This provides explicit disambiguation from child relationships
     */
    private static void parseDataSourceFieldReferences(
        String templateText,
        Set<String> knownDataSourceAliases,
        ParseResult result,
        Set<String> processedFields
    ) {
        // Pattern matches {{@Alias.Field}} or {{@Alias.Field:format}}
        Pattern dataSourcePattern = Pattern.compile('\\{\\{@([\\w.-]+)(?::([^}]+))?\\}\\}');
        Matcher m = dataSourcePattern.matcher(templateText);

        while (m.find()) {
            String fieldPath = m.group(1).trim();
            String formatDirective = m.group(2) != null ? m.group(2).trim() : null;

            if (processedFields.contains('@' + fieldPath)) {
                continue;
            }
            processedFields.add('@' + fieldPath);

            // Extract alias (first part before dot)
            String[] parts = fieldPath.split('\\.');
            String alias = parts[0];

            // Check if this is a known data source alias
            if (!knownDataSourceAliases.contains(alias)) {
                result.warnings.add('Data source reference {{@' + fieldPath + '}} found, but no TemplateDataSource__c configured with alias "' + alias + '"');
                continue;
            }

            // Track data source usage
            result.dataSourceAliasesReferenced.add(alias);

            // Note: Data source fields don't go into mainObjectFields or parentRelationshipFields
            // They're queried separately via CrossObjectQueryBuilder
            // We just track the alias reference here
        }
    }
    
    /**
     * @description Extracts content from all child sections
     */
    private static Set<String> extractChildSectionContent(String templateText) {
        Set<String> content = new Set<String>();
        
        Pattern sectionPattern = Pattern.compile('\\{\\{#(\\w+)\\}\\}([\\s\\S]*?)\\{\\{\\/(\\w+)\\}\\}');
        Matcher m = sectionPattern.matcher(templateText);
        
        while (m.find()) {
            String startTag = m.group(1);
            String sectionContent = m.group(2);
            
            // Skip IF conditionals
            if (!startTag.equalsIgnoreCase('IF')) {
                content.add(sectionContent);
            }
        }
        
        return content;
    }
    
    /**
     * @description Removes child sections from template text
     */
    private static String removeChildSections(String templateText) {
        String result = templateText;
        
        // Remove child relationship sections {{#name}}...{{/name}}
        Pattern sectionPattern = Pattern.compile('\\{\\{#(?!IF\\b)(\\w+)\\}\\}[\\s\\S]*?\\{\\{\\/\\1\\}\\}');
        Matcher m = sectionPattern.matcher(result);
        
        while (m.find()) {
            result = result.replace(m.group(0), '');
        }
        
        // Remove data source sections {{@alias}}...{{/@alias}}
        Pattern dataSourcePattern = Pattern.compile('\\{\\{@([^}]+)\\}\\}[\\s\\S]*?\\{\\{\\/@\\1\\}\\}');
        Matcher dsm = dataSourcePattern.matcher(result);
        
        while (dsm.find()) {
            result = result.replace(dsm.group(0), '');
        }
        
        return result;
    }
    
    /**
     * @description Checks if a field expression is a special GAS-side marker
     */
    private static Boolean isSpecialMarker(String fieldExpr) {
        if (String.isBlank(fieldExpr)) {
            return false;
        }
        
        String upperExpr = fieldExpr.toUpperCase();
        
        if (upperExpr == 'PAGE_BREAK') {
            return true;
        }
        
        if (upperExpr.startsWith('IMAGE:')) {
            return true;
        }
        
        return false;
    }
    
    /**
     * @description Parses a single field expression
     * Supports v3.0 syntax: {{Field:format ?? 'default'}}
     *
     * Parsing order (critical):
     * 1. Split by ?? to extract default value
     * 2. Remove quotes from default value
     * 3. Split field part by : to extract format directive
     * 4. Parse field path for relationship depth
     */
    private static ParsedField parseFieldExpression(
        String fieldExpr,
        String mainObjectName,
        Set<String> knownDataSourceAliases,
        ParseResult result
    ) {
        ParsedField field = new ParsedField();

        // Step 1: Split by ?? to extract default value (v3.0 syntax)
        String fieldPart = fieldExpr;
        String defaultPart = null;

        Integer defaultOpIndex = fieldExpr.indexOf('??');
        if (defaultOpIndex > 0) {
            fieldPart = fieldExpr.substring(0, defaultOpIndex).trim();
            defaultPart = fieldExpr.substring(defaultOpIndex + 2).trim();

            // Step 2: Remove surrounding quotes from default value
            if (String.isNotBlank(defaultPart)) {
                if ((defaultPart.startsWith('"') && defaultPart.endsWith('"')) ||
                    (defaultPart.startsWith('\'') && defaultPart.endsWith('\''))) {
                    defaultPart = defaultPart.substring(1, defaultPart.length() - 1);
                }
                field.defaultValue = defaultPart;
            }
        }

        // Step 3: Extract format directive (after colon) from field part
        String[] parts = fieldPart.split(':', 2); // Limit to 2 parts
        String fieldPath = parts[0].trim();
        field.formatDirective = parts.size() > 1 ? parts[1].trim() : null;

        // Check if it's a system variable
        String firstPart = fieldPath.contains('.') ? fieldPath.split('\\.')[0] : fieldPath;
        Set<String> systemVariables = new Set<String>{
            'TODAY', 'NOW', 'ORG', 'CURRENT_USER', 'ROW_NUM',
            'ORGANIZATION', 'CURRENT_DATE', 'CURRENT_TIME', 'RECORD_ID'
        };

        if (systemVariables.contains(firstPart.toUpperCase())) {
            field.fieldType = FieldType.SYSTEM_VARIABLE;
            field.fieldName = fieldPath;
            field.relationshipPath = fieldPath;
            return field;
        }

        // Check if first part is a known data source alias
        if (knownDataSourceAliases.contains(firstPart)) {
            field.fieldType = FieldType.DATA_SOURCE;
            field.dataSourceAlias = firstPart;

            String[] pathParts = fieldPath.split('\\.');
            if (pathParts.size() > 1) {
                field.fieldName = pathParts[pathParts.size() - 1];
                field.relationshipPath = fieldPath;
            } else {
                field.fieldName = firstPart;
            }
            field.depth = pathParts.size() - 1;
            return field;
        }

        // Step 4: Parse relationship depth
        String[] pathParts = fieldPath.split('\\.');
        field.depth = pathParts.size() - 1;

        if (field.depth == 0) {
            // Main object field: {{QuoteNumber}}
            field.fieldType = FieldType.MAIN_OBJECT;
            field.fieldName = fieldPath;
        } else {
            // Parent relationship: {{Account.Name}} or {{Account.Parent.Name}}
            field.fieldType = FieldType.PARENT_RELATIONSHIP;
            field.relationshipPath = fieldPath;
            field.fieldName = pathParts[pathParts.size() - 1];
        }

        return field;
    }
    
    /**
     * @description Parses child relationship sections with support for nested children
     * Now supports both {{#RelationshipName}} (child relationships) and {{@Alias}} (data sources)
     */
    private static List<ParsedField> parseChildRelationshipsWithNesting(
        String templateText,
        String parentObjectName,
        Set<String> knownDataSourceAliases,
        ParseResult result
    ) {
        List<ParsedField> childRelationships = new List<ParsedField>();
        Set<String> processedRelationships = new Set<String>();

        // Pattern 1: Parse {{#ChildRelationship}} sections (standard child relationships)
        Pattern sectionPattern = Pattern.compile('\\{\\{#(\\w+)\\}\\}([\\s\\S]*?)\\{\\{\\/(\\1)\\}\\}');
        Matcher m = sectionPattern.matcher(templateText);

        while (m.find()) {
            String startTag = m.group(1);
            String sectionContent = m.group(2);

            // Skip IF conditionals
            if (startTag.equalsIgnoreCase('IF')) {
                continue;
            }

            // Data sources MUST use @ syntax - {{#Alias}} is no longer supported
            if (knownDataSourceAliases.contains(startTag)) {
                result.errors.add('Data source "' + startTag + '" uses invalid syntax {{#' + startTag + '}}. ' +
                                 'Data sources must use {{@' + startTag + '}} syntax. Update your template.');
                continue;
            }
            
            // Skip if already processed at this level
            if (processedRelationships.contains(startTag)) {
                continue;
            }
            processedRelationships.add(startTag);
            
            // Get child object name from schema
            String childObjectName = getChildObjectName(parentObjectName, startTag);
            
            if (String.isBlank(childObjectName)) {
                childObjectName = 'Unknown';
            }
            
            ParsedField childRel = new ParsedField();
            childRel.fieldType = FieldType.CHILD_RELATIONSHIP;
            childRel.fieldName = startTag;
            childRel.parentRelationshipName = parentObjectName;
            
            // Parse fields within the section
            String sectionWithoutNested = removeChildSections(sectionContent);
            childRel.childFields = parseChildSectionFields(sectionWithoutNested, childObjectName, knownDataSourceAliases, result);
            
            // Recursively parse nested child relationships
            childRel.nestedChildren = parseNestedChildRelationships(sectionContent, childObjectName, knownDataSourceAliases, result);
            
            childRelationships.add(childRel);
        }

        // Pattern 2: Parse {{@Alias}} sections (new data source syntax)
        Pattern dataSourceSectionPattern = Pattern.compile('\\{\\{@(\\w+)\\}\\}([\\s\\S]*?)\\{\\{\\/@(\\1)\\}\\}');
        Matcher dsm = dataSourceSectionPattern.matcher(templateText);

        while (dsm.find()) {
            String alias = dsm.group(1);

            // Track data source usage
            if (knownDataSourceAliases.contains(alias)) {
                result.dataSourceAliasesReferenced.add(alias);
            } else {
                result.warnings.add('Data source section {{@' + alias + '}} found, but no TemplateDataSource__c configured with this alias');
            }
        }

        return childRelationships;
    }
    
    /**
     * @description Parses nested child relationships within a parent section
     */
    private static List<ParsedField> parseNestedChildRelationships(
        String sectionContent, 
        String parentChildObjectName, 
        Set<String> knownDataSourceAliases,
        ParseResult result
    ) {
        List<ParsedField> nestedRelationships = new List<ParsedField>();
        Set<String> processedNested = new Set<String>();
        
        Pattern nestedPattern = Pattern.compile('\\{\\{#(\\w+)\\}\\}([\\s\\S]*?)\\{\\{\\/(\\1)\\}\\}');
        Matcher m = nestedPattern.matcher(sectionContent);
        
        while (m.find()) {
            String nestedTag = m.group(1);
            String nestedContent = m.group(2);
            
            if (nestedTag.equalsIgnoreCase('IF')) {
                continue;
            }
            
            if (knownDataSourceAliases.contains(nestedTag)) {
                result.dataSourceAliasesReferenced.add(nestedTag);
                continue;
            }
            
            if (processedNested.contains(nestedTag)) {
                continue;
            }
            processedNested.add(nestedTag);
            
            String grandchildObjectName = getChildObjectName(parentChildObjectName, nestedTag);
            
            if (String.isBlank(grandchildObjectName)) {
                grandchildObjectName = 'Unknown';
            }
            
            ParsedField nestedRel = new ParsedField();
            nestedRel.fieldType = FieldType.CHILD_RELATIONSHIP;
            nestedRel.fieldName = nestedTag;
            nestedRel.parentRelationshipName = parentChildObjectName;
            
            nestedRel.childFields = parseChildSectionFields(nestedContent, grandchildObjectName, knownDataSourceAliases, result);
            
            // Support another level of nesting
            nestedRel.nestedChildren = parseNestedChildRelationships(nestedContent, grandchildObjectName, knownDataSourceAliases, result);
            
            nestedRelationships.add(nestedRel);
        }
        
        return nestedRelationships;
    }
    
    /**
     * @description Parses fields within a child relationship section
     */
    private static List<ParsedField> parseChildSectionFields(
        String sectionContent, 
        String childObjectName, 
        Set<String> knownDataSourceAliases,
        ParseResult result
    ) {
        List<ParsedField> fields = new List<ParsedField>();
        Set<String> processedFields = new Set<String>();
        
        Pattern fieldPattern = Pattern.compile('\\{\\{([^#/@}]+)\\}\\}');
        Matcher m = fieldPattern.matcher(sectionContent);
        
        while (m.find()) {
            String fieldExpr = m.group(1).trim();
            
            // Skip conditionals (v3.0 syntax)
            if (fieldExpr.startsWithIgnoreCase('IF ') ||
                fieldExpr.startsWithIgnoreCase('ELSEIF ') ||
                fieldExpr.equalsIgnoreCase('ELSE') ||
                fieldExpr.startsWithIgnoreCase('/IF')) {
                continue;
            }
            
            if (isSpecialMarker(fieldExpr)) {
                continue;
            }
            
            if (processedFields.contains(fieldExpr)) {
                continue;
            }
            processedFields.add(fieldExpr);
            
            ParsedField parsed = parseFieldExpression(fieldExpr, childObjectName, knownDataSourceAliases, result);
            fields.add(parsed);
        }
        
        // Parse IMAGE markers in child sections
        Pattern imagePattern = Pattern.compile('(?i)\\{\\{IMAGE:([^:}]+)(?::\\d+x\\d+)?\\}\\}');
        Matcher imgMatcher = imagePattern.matcher(sectionContent);
        
        while (imgMatcher.find()) {
            String fieldPath = imgMatcher.group(1).trim();
            
            if (processedFields.contains('IMAGE:' + fieldPath)) {
                continue;
            }
            processedFields.add('IMAGE:' + fieldPath);
            
            ParsedField parsed = parseFieldExpression(fieldPath, childObjectName, knownDataSourceAliases, result);
            fields.add(parsed);
        }
        
        return fields;
    }
    
    /**
     * @description Validates that child relationships are properly closed
     */
    private static void validateChildRelationships(String templateText, ParseResult result) {
        for (ParsedField childRel : result.childRelationships) {
            String startTag = '{{#' + childRel.fieldName + '}}';
            String endTag = '{{/' + childRel.fieldName + '}}';
            
            Integer startCount = templateText.countMatches(startTag);
            Integer endCount = templateText.countMatches(endTag);
            
            if (startCount != endCount) {
                result.errors.add('Mismatched section tags for ' + childRel.fieldName + 
                                ': ' + startCount + ' opening, ' + endCount + ' closing');
            }
        }
    }
    
    /**
     * @description Gets the child object name from a relationship name
     */
    public static String getChildObjectName(String parentObjectName, String relationshipName) {
        try {
            List<Schema.ChildRelationship> childRels = SchemaCache.getChildRelationships(parentObjectName);

            for (Schema.ChildRelationship childRel : childRels) {
                if (childRel.getRelationshipName() == relationshipName) {
                    return childRel.getChildSObject().getDescribe().getName();
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not get child object name: ' + e.getMessage());
        }

        return null;
    }

    /**
     * @description Counts occurrences of a substring in a string
     * @param text The text to search in
     * @param searchString The substring to count
     * @return Integer The number of occurrences
     */
    private static Integer countOccurrences(String text, String searchString) {
        if (String.isBlank(text) || String.isBlank(searchString)) {
            return 0;
        }
        return text.countMatches(searchString);
    }

    /**
     * @description Calculates the maximum nesting depth of section tags
     * Uses a simple stack-based approach to track nesting levels
     * @param templateText The template text to analyze
     * @return Integer The maximum nesting depth found
     */
    private static Integer calculateMaxNestingDepth(String templateText) {
        Integer maxDepth = 0;
        Integer currentDepth = 0;

        // Pattern to match section start and end tags
        Pattern sectionPattern = Pattern.compile('\\{\\{(#|/)([^}]+)\\}\\}');
        Matcher m = sectionPattern.matcher(templateText);

        while (m.find()) {
            String marker = m.group(1);  // # or /
            String tagName = m.group(2).trim();

            // Skip IF conditionals for depth calculation (they don't create object hierarchy)
            if (tagName.startsWithIgnoreCase('IF') || tagName.equalsIgnoreCase('ELSE')) {
                continue;
            }

            if (marker == '#') {
                // Opening tag
                currentDepth++;
                if (currentDepth > maxDepth) {
                    maxDepth = currentDepth;
                }
            } else if (marker == '/') {
                // Closing tag
                currentDepth--;
                if (currentDepth < 0) {
                    // Mismatched tags - reset to 0
                    currentDepth = 0;
                }
            }
        }

        return maxDepth;
    }
}
