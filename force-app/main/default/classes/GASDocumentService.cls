/**
 * @description Service for communicating with Google Apps Script Web App.
 * Handles HTTP communication with the GAS middleware including:
 * - Redirect handling (GAS returns 302 to googleusercontent.com)
 * - Retry logic for transient failures
 * - Named Credential support (recommended) or Custom Metadata fallback
 *
 * IMPORTANT: GAS Web Apps return 302 redirects that must be followed with GET
 * (not POST) to retrieve the actual response.
 *
 * API KEY: The API key is passed in the request body (not headers) because
 * headers are not preserved during GAS redirects.
 *
 * @author Document Generation Framework
 * @since 2024
 */
public with sharing class GASDocumentService {

    private static final Integer DEFAULT_TIMEOUT_MS = 120000;
    private static final Integer MAX_RETRIES = 2;
    private static final Integer MAX_REDIRECTS = 5;

    // Named Credential name (if configured)
    private static final String NAMED_CREDENTIAL = 'GAS_Document_Generator';

    /**
     * @description Custom exception for GAS communication errors
     */
    public class GASException extends Exception {}

    /**
     * @description Request payload sent to GAS
     */
    public class GenerationRequest {
        public String templateId;
        public String outputFileName;
        public Map<String, Object> recordData;
        public Map<String, List<Map<String, Object>>> childData;
        public Map<String, Object> systemVariables;
        public Map<String, String> additionalFields;
        public Map<String, Object> crossObjectData;  // For TemplateDataSource__c queries
        public Id parentRecordId;  // For direct upload - record to link file to
        public Boolean useDirectUpload = false;  // Enable direct upload to Salesforce

        public GenerationRequest() {
            this.recordData = new Map<String, Object>();
            this.childData = new Map<String, List<Map<String, Object>>>();
            this.systemVariables = new Map<String, Object>();
            this.additionalFields = new Map<String, String>();
            this.crossObjectData = new Map<String, Object>();
        }
    }

    /**
     * @description Response from GAS (Direct Upload mode only)
     * GAS uploads PDF directly to Salesforce and returns ContentDocumentId
     */
    public class GenerationResponse {
        public Boolean success;
        public String fileName;
        public String errorMessage;
        public List<String> warnings;
        public Long processingTimeMs;
        public Boolean uploadedDirectly;  // Should always be true in production
        public Id contentDocumentId;      // The uploaded file's ContentDocumentId
        public Id contentVersionId;       // The uploaded file's ContentVersionId

        public GenerationResponse() {
            this.warnings = new List<String>();
            this.uploadedDirectly = false;
        }
    }

    /**
     * @description Generates a PDF document via GAS middleware
     * GAS uploads the PDF directly to Salesforce via JWT authentication
     * @param request The generation request with template ID and merge data
     * @return GenerationResponse containing ContentDocumentId (no Base64)
     */
    public static GenerationResponse generateDocument(GenerationRequest request) {
        GenerationResponse response = new GenerationResponse();

        try {
            // Validate request
            if (String.isBlank(request.templateId)) {
                throw new GASException('Template ID is required');
            }

            // Build request payload
            Map<String, Object> payload = new Map<String, Object>{
                'action' => 'generate',
                'templateId' => request.templateId,
                'outputFileName' => request.outputFileName,
                'recordData' => request.recordData,
                'childData' => request.childData,
                'systemVariables' => request.systemVariables,
                'additionalFields' => request.additionalFields,
                'crossObjectData' => request.crossObjectData
            };

            // Add direct upload configuration if enabled
            if (request.useDirectUpload) {
                payload.put('directUpload', new Map<String, Object>{
                    'enabled' => true,
                    'parentRecordId' => request.parentRecordId
                });
                System.debug(LoggingLevel.INFO, '=== DIRECT UPLOAD ENABLED ===');
            }

            // Add API key to payload (not header - headers lost on redirect)
            String apiKey = GoogleAuthService.getGASApiKey();
            if (String.isNotBlank(apiKey)) {
                payload.put('apiKey', apiKey);
            }

            // Debug: Log the payload being sent to GAS
            System.debug(LoggingLevel.INFO, '=== GAS REQUEST PAYLOAD ===');
            System.debug(LoggingLevel.INFO, JSON.serializePretty(payload));

            // Make callout with retry and redirect handling
            HttpResponse httpResponse = executeCallout(payload);

            // Debug: Log GAS response (excluding base64 PDF to keep log readable)
            System.debug(LoggingLevel.INFO, '=== GAS RESPONSE: status=' + httpResponse.getStatusCode() + ' ===');

            // Parse response
            response = parseGASResponse(httpResponse);

        } catch (GASException e) {
            response.success = false;
            response.errorMessage = e.getMessage();
        } catch (CalloutException e) {
            response.success = false;
            response.errorMessage = 'Failed to connect to GAS: ' + e.getMessage();
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = 'Unexpected error: ' + e.getMessage();
        }

        return response;
    }

    /**
     * @description Validates a template via GAS
     * @param templateId The Google Doc template ID
     * @return Map containing validation results
     */
    public static Map<String, Object> validateTemplate(String templateId) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            Map<String, Object> payload = new Map<String, Object>{
                'action' => 'validate',
                'templateId' => templateId
            };

            // Add API key to payload
            String apiKey = GoogleAuthService.getGASApiKey();
            if (String.isNotBlank(apiKey)) {
                payload.put('apiKey', apiKey);
            }

            HttpResponse httpResponse = executeCallout(payload);

            if (httpResponse.getStatusCode() == 200) {
                result = (Map<String, Object>) JSON.deserializeUntyped(httpResponse.getBody());
            } else {
                result.put('success', false);
                result.put('error', 'Validation failed: ' + httpResponse.getBody());
            }

        } catch (Exception e) {
            result.put('success', false);
            result.put('error', e.getMessage());
        }

        return result;
    }

    /**
     * @description Executes HTTP callout with retry and redirect handling
     */
    private static HttpResponse executeCallout(Map<String, Object> payload) {
        HttpResponse response;
        Integer attempts = 0;

        while (attempts < MAX_RETRIES) {
            attempts++;

            HttpRequest request = buildRequest(payload);
            Http http = new Http();
            response = http.send(request);

            System.debug(LoggingLevel.DEBUG, 'GAS initial response status: ' + response.getStatusCode());

            // Handle redirects - GAS returns 302 that must be followed with GET
            response = followGASRedirects(response);

            // Success
            if (response.getStatusCode() == 200) {
                return response;
            }

            // Client error - don't retry
            if (response.getStatusCode() >= 400 && response.getStatusCode() < 500) {
                return response;
            }

            // Server error - retry
            if (attempts < MAX_RETRIES) {
                System.debug(LoggingLevel.WARN,
                    'GAS returned ' + response.getStatusCode() + ', retrying (attempt ' + attempts + ')');
            }
        }

        return response;
    }

    /**
     * @description Builds the initial HTTP request
     */
    private static HttpRequest buildRequest(Map<String, Object> payload) {
        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setTimeout(DEFAULT_TIMEOUT_MS);
        request.setHeader('Content-Type', 'application/json');

        // Try Named Credential first, fall back to Custom Metadata
        if (isNamedCredentialConfigured()) {
            request.setEndpoint('callout:' + NAMED_CREDENTIAL);
        } else {
            String gasUrl = GoogleAuthService.getGASWebAppUrl();

            if (String.isBlank(gasUrl)) {
                throw new GASException('GAS Web App URL not configured. Set up Named Credential "' +
                    NAMED_CREDENTIAL + '" or configure GASWebAppUrl__c in DocumentGenConfig__c Custom Setting.');
            }

            request.setEndpoint(gasUrl);
        }

        // Add Salesforce context headers for audit (informational only)
        request.setHeader('X-SF-Org-Id', UserInfo.getOrganizationId());
        request.setHeader('X-SF-User-Id', UserInfo.getUserId());

        if (payload != null) {
            request.setBody(JSON.serialize(payload));
        }

        return request;
    }

    /**
     * @description Follows GAS redirects correctly
     *
     * IMPORTANT: GAS Web Apps work like this:
     * 1. You POST to script.google.com/macros/s/xxx/exec
     * 2. GAS processes your request and generates a response
     * 3. GAS returns 302 redirect to script.googleusercontent.com/... with the response
     * 4. You must GET that redirect URL to retrieve the actual response
     *
     * The redirect URL contains the response - it's NOT asking you to POST again!
     */
    private static HttpResponse followGASRedirects(HttpResponse response) {
        Integer redirectCount = 0;
        Http http = new Http();

        while (isRedirect(response.getStatusCode()) && redirectCount < MAX_REDIRECTS) {
            String redirectUrl = response.getHeader('Location');

            if (String.isBlank(redirectUrl)) {
                System.debug(LoggingLevel.WARN, 'Redirect without Location header');
                break;
            }

            System.debug(LoggingLevel.DEBUG, 'Following GAS redirect #' + (redirectCount + 1) + ' to: ' + redirectUrl);

            // CRITICAL: Follow GAS redirects with GET, not POST
            // The redirect URL contains the response data
            HttpRequest redirectRequest = new HttpRequest();
            redirectRequest.setEndpoint(redirectUrl);
            redirectRequest.setMethod('GET');  // Must be GET for GAS redirects!
            redirectRequest.setTimeout(DEFAULT_TIMEOUT_MS);

            response = http.send(redirectRequest);
            redirectCount++;

            System.debug(LoggingLevel.DEBUG, 'Redirect response status: ' + response.getStatusCode());
        }

        return response;
    }

    /**
     * @description Checks if status code is a redirect
     */
    private static Boolean isRedirect(Integer statusCode) {
        return statusCode == 301 || statusCode == 302 || statusCode == 303 ||
               statusCode == 307 || statusCode == 308;
    }

    /**
     * @description Checks if Named Credential is configured
     */
    private static Boolean isNamedCredentialConfigured() {
        try {
            // Query for Named Credential existence
            List<NamedCredential> ncs = [
                SELECT Id FROM NamedCredential
                WHERE DeveloperName = :NAMED_CREDENTIAL
                LIMIT 1
            ];
            return !ncs.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Parses GAS HTTP response into GenerationResponse
     */
    private static GenerationResponse parseGASResponse(HttpResponse httpResponse) {
        GenerationResponse response = new GenerationResponse();

        if (httpResponse.getStatusCode() != 200) {
            response.success = false;

            // Check if it's an HTML error page
            String body = httpResponse.getBody();
            if (body != null && body.contains('<!DOCTYPE html>')) {
                response.errorMessage = 'GAS returned error page (status ' + httpResponse.getStatusCode() +
                                       '). Check your GAS deployment and permissions.';
            } else {
                response.errorMessage = 'GAS returned status ' + httpResponse.getStatusCode() + ': ' + body;
            }
            return response;
        }

        try {
            String body = httpResponse.getBody();

            // Check if response is HTML (error page) instead of JSON
            if (body != null && (body.trim().startsWith('<!DOCTYPE') || body.trim().startsWith('<html'))) {
                response.success = false;
                response.errorMessage = 'GAS returned HTML instead of JSON. Check your GAS deployment.';
                return response;
            }

            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(body);

            response.success = jsonResponse.get('success') == true;
            response.fileName = (String) jsonResponse.get('fileName');
            response.errorMessage = (String) jsonResponse.get('error');

            // Parse direct upload response fields (required in production)
            response.uploadedDirectly = jsonResponse.get('uploadedDirectly') == true;
            if (response.uploadedDirectly) {
                String contentDocId = (String) jsonResponse.get('contentDocumentId');
                String contentVerseId = (String) jsonResponse.get('contentVersionId');
                response.contentDocumentId = String.isNotBlank(contentDocId) ? Id.valueOf(contentDocId) : null;
                response.contentVersionId = String.isNotBlank(contentVerseId) ? Id.valueOf(contentVerseId) : null;
                System.debug(LoggingLevel.INFO, '=== DIRECT UPLOAD SUCCESS: ContentDocumentId=' + response.contentDocumentId + ' ===');
            } else if (response.success) {
                // GAS returned success but didn't upload directly - this is a configuration error
                System.debug(LoggingLevel.ERROR, '=== GAS did not perform direct upload - check JWT configuration ===');
            }

            if (jsonResponse.containsKey('processingTimeMs')) {
                response.processingTimeMs = Long.valueOf(String.valueOf(jsonResponse.get('processingTimeMs')));
            }

            if (jsonResponse.containsKey('warnings')) {
                List<Object> warningsList = (List<Object>) jsonResponse.get('warnings');
                for (Object w : warningsList) {
                    response.warnings.add(String.valueOf(w));
                }
            }

            // Log GAS version to verify deployment
            if (jsonResponse.containsKey('gasVersion')) {
                System.debug(LoggingLevel.INFO, '=== GAS VERSION: ' + jsonResponse.get('gasVersion') + ' ===');
            }

            // Log GAS debug info for troubleshooting
            if (jsonResponse.containsKey('debugInfo')) {
                System.debug(LoggingLevel.INFO, '=== GAS DEBUG INFO ===');
                List<Object> debugList = (List<Object>) jsonResponse.get('debugInfo');
                for (Object item : debugList) {
                    System.debug(LoggingLevel.INFO, '  ' + String.valueOf(item));
                }
            }

        } catch (Exception e) {
            response.success = false;
            response.errorMessage = 'Failed to parse GAS response: ' + e.getMessage();
        }

        return response;
    }

    /**
     * @description Health check for GAS endpoint
     * @return Boolean true if GAS is reachable and responding
     */
    public static Boolean healthCheck() {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setTimeout(10000);

            if (isNamedCredentialConfigured()) {
                request.setEndpoint('callout:' + NAMED_CREDENTIAL + '?action=health');
            } else {
                String gasUrl = GoogleAuthService.getGASWebAppUrl();
                if (String.isBlank(gasUrl)) {
                    return false;
                }
                request.setEndpoint(gasUrl + '?action=health');
            }

            Http http = new Http();
            HttpResponse response = http.send(request);

            // Follow redirects for health check too
            response = followGASRedirects(response);

            return response.getStatusCode() == 200;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GAS health check failed: ' + e.getMessage());
            return false;
        }
    }
}
