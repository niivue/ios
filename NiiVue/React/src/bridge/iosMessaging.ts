/**
 * iOS WKWebView messaging bridge
 *
 * Provides a unified interface for sending messages from the React app
 * to the native iOS Swift code via WKWebView message handlers.
 *
 * In development (non-iOS) environments, messages are logged to console.
 */

// Known message handler names (matching Swift WKScriptMessageHandler names)
export type MessageHandlerName =
  | 'updateUI'
  | 'logMessage'
  | 'locationChange'
  | 'finishedLoading'  // Task 7: Event-driven ready handshake
  | 'volumeLoaded'     // Task 7.5: Volume notifications

/**
 * Check if we're running inside an iOS WKWebView
 */
export function isIOSWebView(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.webkit !== 'undefined' &&
    typeof window.webkit?.messageHandlers !== 'undefined'
  )
}

/**
 * Post a message to the iOS native layer
 *
 * @param handler - The name of the message handler registered in Swift
 * @param message - The message payload (will be JSON stringified)
 */
export function postToIOS(handler: MessageHandlerName | string, message: unknown): void {
  const jsonString = JSON.stringify(message)

  if (isIOSWebView()) {
    const messageHandler = window.webkit?.messageHandlers?.[handler]
    if (messageHandler?.postMessage) {
      messageHandler.postMessage(jsonString)
    }
  } else {
    // Development mode: log to console for debugging
    console.log(`[postToIOS] ${handler}:`, jsonString)
  }
}

/**
 * Convenience function to post a log message to iOS
 */
export function logToIOS(level: 'debug' | 'info' | 'warn' | 'error', message: string): void {
  postToIOS('logMessage', { level, message, timestamp: Date.now() })
}

/**
 * Notify iOS that the web view is ready
 */
export function notifyReady(): void {
  postToIOS('updateUI', { type: 'ready', timestamp: Date.now() })
}
