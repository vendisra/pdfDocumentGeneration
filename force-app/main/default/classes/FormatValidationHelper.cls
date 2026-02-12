/**
 * @description Helper class for validating format directives against field types
 * Ensures that template format directives (e.g., {{Amount:currency}}) are compatible
 * with the actual Salesforce field types to prevent runtime errors
 *
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class FormatValidationHelper {

    /**
     * @description Map of field types to their compatible format directives
     */
    private static final Map<Schema.DisplayType, Set<String>> COMPATIBLE_FORMATS = new Map<Schema.DisplayType, Set<String>>{
        Schema.DisplayType.CURRENCY => new Set<String>{'currency', 'number', 'decimal'},
        Schema.DisplayType.DOUBLE => new Set<String>{'number', 'decimal', 'currency'},
        Schema.DisplayType.INTEGER => new Set<String>{'number', 'decimal'},
        Schema.DisplayType.PERCENT => new Set<String>{'percent', 'number', 'decimal'},
        Schema.DisplayType.DATE => new Set<String>{'date', 'short', 'medium', 'long', 'full'},
        Schema.DisplayType.DATETIME => new Set<String>{'datetime', 'date', 'time', 'short', 'medium', 'long', 'full'},
        Schema.DisplayType.TIME => new Set<String>{'time', 'short', 'medium'},
        Schema.DisplayType.STRING => new Set<String>{'uppercase', 'lowercase', 'capitalize', 'trim'},
        Schema.DisplayType.TEXTAREA => new Set<String>{'uppercase', 'lowercase', 'capitalize', 'trim'},
        Schema.DisplayType.EMAIL => new Set<String>{'lowercase', 'trim'},
        Schema.DisplayType.PHONE => new Set<String>{'trim'},
        Schema.DisplayType.URL => new Set<String>{'lowercase', 'trim'},
        Schema.DisplayType.BOOLEAN => new Set<String>{'boolean', 'yesno', 'truefalse', '10'}
    };

    /**
     * @description Validates if a format directive is compatible with a field type
     * @param formatDirective The format directive (e.g., 'currency', 'date')
     * @param fieldType The Salesforce field type
     * @return ValidationResult Result indicating compatibility and any warnings
     */
    public static ValidationResult validateFormatCompatibility(String formatDirective, Schema.DisplayType fieldType) {
        ValidationResult result = new ValidationResult();
        result.isCompatible = true;

        if (String.isBlank(formatDirective)) {
            // No format specified - always valid (will use auto-formatting)
            return result;
        }

        String lowerFormat = formatDirective.toLowerCase().trim();

        // Check if this field type has any format restrictions
        if (!COMPATIBLE_FORMATS.containsKey(fieldType)) {
            // Field type doesn't support formatting (e.g., PICKLIST, REFERENCE)
            // This is a warning, not an error - GAS will just convert to string
            result.warningMessage = 'Format directive "' + formatDirective + '" is applied to ' + fieldType.name() +
                                   ' field type, which doesn\'t support explicit formatting. Value will be converted to text.';
            return result;
        }

        Set<String> compatibleFormats = COMPATIBLE_FORMATS.get(fieldType);

        if (!compatibleFormats.contains(lowerFormat)) {
            // Format not in compatible list
            result.isCompatible = false;
            result.errorMessage = 'Format directive "' + formatDirective + '" is not compatible with ' + fieldType.name() +
                                 ' field type. Compatible formats: ' + String.join(new List<String>(compatibleFormats), ', ');
        }

        return result;
    }

    /**
     * @description Validates if a format directive exists and is recognized
     * @param formatDirective The format directive to validate
     * @return Boolean True if the format is recognized
     */
    public static Boolean isRecognizedFormat(String formatDirective) {
        if (String.isBlank(formatDirective)) {
            return false;
        }

        String lowerFormat = formatDirective.toLowerCase().trim();

        // Collect all recognized formats across all field types
        Set<String> allFormats = new Set<String>();
        for (Set<String> formats : COMPATIBLE_FORMATS.values()) {
            allFormats.addAll(formats);
        }

        return allFormats.contains(lowerFormat);
    }

    /**
     * @description Gets suggested compatible formats for a field type
     * @param fieldType The Salesforce field type
     * @return List<String> List of compatible format directives
     */
    public static List<String> getSuggestedFormats(Schema.DisplayType fieldType) {
        if (COMPATIBLE_FORMATS.containsKey(fieldType)) {
            return new List<String>(COMPATIBLE_FORMATS.get(fieldType));
        }
        return new List<String>();
    }

    /**
     * @description Result class for format validation
     */
    public class ValidationResult {
        public Boolean isCompatible { get; set; }
        public String errorMessage { get; set; }
        public String warningMessage { get; set; }

        public ValidationResult() {
            this.isCompatible = true;
        }

        public Boolean hasError() {
            return !isCompatible && String.isNotBlank(errorMessage);
        }

        public Boolean hasWarning() {
            return String.isNotBlank(warningMessage);
        }
    }
}
