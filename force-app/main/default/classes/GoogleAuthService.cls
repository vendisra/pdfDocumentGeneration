/**
 * @description Service class for document generation configuration.
 * Retrieves configuration from Custom Settings for GAS Web App integration.
 *
 * SETUP REQUIRED:
 * 1. Deploy Google Apps Script Web App
 * 2. Go to Setup → Custom Settings → Document Generation Config → Manage → New
 * 3. Set GAS Web App URL to the deployed GAS Web App URL
 * 4. Optionally set GAS API Key for authentication
 *
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class GoogleAuthService {

    /**
     * @description Custom exception for configuration errors
     */
    public class ConfigurationException extends Exception {}

    /**
     * @description Gets document generation config from Custom Settings
     * @return DocumentGenConfig__c The config
     */
    public static DocumentGenConfig__c getConfig() {
        DocumentGenConfig__c config = DocumentGenConfig__c.getInstance();

        if (config == null) {
            throw new ConfigurationException(
                'DocumentGenConfig__c custom setting not found. ' +
                'Please go to Setup → Custom Settings → Document Generation Config → Manage → New to create the configuration.'
            );
        }

        return config;
    }

    /**
     * @description Gets the GAS Web App URL
     * @return String The GAS Web App endpoint URL
     */
    public static String getGASWebAppUrl() {
        return getConfig().GASWebAppUrl__c;
    }

    /**
     * @description Gets the GAS API Key for authentication
     * @return String The API key (may be null if not using API key auth)
     */
    public static String getGASApiKey() {
        return getConfig().GASApiKey__c;
    }

    /**
     * @description Gets the GAS callout timeout in milliseconds
     * @return Integer Timeout in ms (default 120000)
     */
    public static Integer getGASTimeout() {
        Decimal timeout = getConfig().GASTimeoutMs__c;
        return timeout != null ? Integer.valueOf(timeout) : 120000;
    }

    /**
     * @description Checks if logging is enabled
     * @return Boolean True if logging is enabled
     */
    public static Boolean isLoggingEnabled() {
        return getConfig().EnableLogging__c == true;
    }

    /**
     * @description Gets max documents per batch
     * @return Integer The max docs per batch (default 10)
     */
    public static Integer getMaxDocsPerBatch() {
        Decimal maxDocs = getConfig().MaxDocsPerBatch__c;
        return maxDocs != null ? Integer.valueOf(maxDocs) : 10;
    }

    /**
     * @description Validates that configuration is complete
     * @return List<String> List of configuration errors (empty if valid)
     */
    public static List<String> validateConfiguration() {
        List<String> errors = new List<String>();

        try {
            DocumentGenConfig__c config = getConfig();

            if (String.isBlank(config.GASWebAppUrl__c)) {
                errors.add('GASWebAppUrl__c is not configured');
            } else if (!config.GASWebAppUrl__c.startsWith('https://')) {
                errors.add('GASWebAppUrl__c must use HTTPS');
            }

        } catch (ConfigurationException e) {
            errors.add(e.getMessage());
        }

        return errors;
    }
}
