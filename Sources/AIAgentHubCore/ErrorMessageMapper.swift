import Foundation

/// Maps framework-internal errors to user-facing messages so the UI never shows
/// `error.localizedDescription` (which is often empty or raw `Error` text).
public enum ErrorMessageMapper {
    /// Return a human-readable explanation and, where possible, a suggested action.
    public static func message(for error: any Error) -> (title: String, detail: String) {
        switch error {

        // === Model configuration ===
        case ModelConfigurationError.missingAPIKey:
            return ("API key missing", "A model configuration does not have a stored API key. Open the Models tab to add one.")
        case ModelConfigurationError.noEnabledModel:
            return ("No model available", "Enable at least one model in the Models tab before sending messages.")
        case ModelConfigurationError.emptyName:
            return ("Name required", "Each model needs a display name.")
        case ModelConfigurationError.emptyModelName:
            return ("Model name required", "Enter the model identifier (e.g. gpt-4.1-mini).")
        case ModelConfigurationError.temperatureOutOfRange:
            return ("Invalid temperature", "Temperature must be between 0 and 2.")
        case ModelConfigurationError.maxTokensOutOfRange:
            return ("Invalid max tokens", "Max tokens must be between 1 and 200,000.")

        // === Orchestrator ===
        case ChatOrchestratorError.thirdPartyDisabled(let provider):
            return ("\(provider.displayName) blocked", "Third-party API calls are disabled in Privacy settings. Turn on 'Allow third-party API calls' or switch to an on-device model.")
        case ChatOrchestratorError.noUserMessageToReplay:
            return ("Nothing to regenerate", "There is no previous message to re-run.")

        // === Tool ===
        case ToolExecutionError.toolNotFound(let name):
            return ("Tool not found", "No tool named '\(name)' is registered.")
        case ToolExecutionError.authorizationCancelled:
            return ("Action cancelled", "The tool execution was not approved.")
        case ToolExecutionError.invalidArguments(let detail):
            return ("Invalid arguments", detail)

        // === Auth / network ===
        case AIHTTPClientError.missingEndpoint:
            return ("Endpoint missing", "Set a custom endpoint or use the provider's default.")
        case AIHTTPClientError.missingAPIKey:
            return ("API key missing", "Add this provider's API key in the Models tab.")
        case AIHTTPClientError.invalidResponse:
            return ("Unexpected response", "The provider returned data we couldn't understand. The model may be misconfigured.")
        case AIHTTPClientError.httpStatus(let code):
            return httpStatusMessage(code)

        // === Cancellation ===
        case is CancellationError:
            return ("Generation cancelled", "Stopped as requested.")

        // === Fallback ===
        default:
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                return nsURLErrorMessage(nsError)
            }
            let desc = error.localizedDescription
            if desc.isEmpty || desc == "The operation couldn’t be completed." {
                return ("Something went wrong", "An unexpected error occurred. If it keeps happening, try a different model.")
            }
            return ("Something went wrong", desc)
        }
    }

    private static func httpStatusMessage(_ code: Int) -> (title: String, detail: String) {
        switch code {
        case 401, 403:
            return ("Authentication failed", "The API key may be invalid or expired. Check the Models tab.")
        case 429:
            return ("Rate limited", "The provider returned a rate-limit error. Wait a moment and try again.")
        case 500...599:
            return ("Provider error", "The AI provider's servers returned an error (HTTP \(code)). Try again in a few minutes.")
        case 400:
            return ("Bad request", "The request could not be processed. The model name or parameters may be incorrect.")
        default:
            return ("HTTP \(code)", "The provider returned HTTP \(code).")
        }
    }

    private static func nsURLErrorMessage(_ error: NSError) -> (title: String, detail: String) {
        switch error.code {
        case NSURLErrorTimedOut:
            return ("Request timed out", "The provider did not respond in time. Check your network connection and try again.")
        case NSURLErrorNotConnectedToInternet:
            return ("No internet connection", "Check your network settings and try again.")
        case NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return ("Cannot reach provider", "The provider's endpoint could not be reached. Check the URL in the Models tab.")
        case NSURLErrorSecureConnectionFailed:
            return ("Secure connection failed", "The provider's SSL certificate could not be verified.")
        default:
            return ("Network error", error.localizedDescription)
        }
    }
}