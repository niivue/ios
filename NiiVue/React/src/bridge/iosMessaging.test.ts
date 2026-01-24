import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// Tests written FIRST following TDD
describe('iosMessaging', () => {
  // Store original window.webkit
  const originalWebkit = window.webkit

  beforeEach(() => {
    // Reset window.webkit before each test
    // @ts-expect-error - modifying window for testing
    delete window.webkit
  })

  afterEach(() => {
    // Restore original window.webkit
    // @ts-expect-error - modifying window for testing
    window.webkit = originalWebkit
    vi.clearAllMocks()
  })

  describe('isIOSWebView', () => {
    it('should return true when window.webkit.messageHandlers exists', async () => {
      // Arrange: Set up mock iOS environment
      // @ts-expect-error - mocking webkit for testing
      window.webkit = {
        messageHandlers: {
          updateUI: { postMessage: vi.fn() },
        },
      }

      // Act: Import module after setting up window
      const { isIOSWebView } = await import('./iosMessaging')

      // Assert
      expect(isIOSWebView()).toBe(true)
    })

    it('should return false when window.webkit is undefined', async () => {
      // Arrange: window.webkit is deleted in beforeEach

      // Act
      const { isIOSWebView } = await import('./iosMessaging')

      // Assert
      expect(isIOSWebView()).toBe(false)
    })

    it('should return false when window.webkit.messageHandlers is undefined', async () => {
      // Arrange
      // @ts-expect-error - mocking partial webkit for testing
      window.webkit = {}

      // Act
      const { isIOSWebView } = await import('./iosMessaging')

      // Assert
      expect(isIOSWebView()).toBe(false)
    })
  })

  describe('postToIOS', () => {
    it('should call postMessage on the specified handler when in iOS WebView', async () => {
      // Arrange
      const mockPostMessage = vi.fn()
      // @ts-expect-error - mocking webkit for testing
      window.webkit = {
        messageHandlers: {
          updateUI: { postMessage: mockPostMessage },
        },
      }

      // Act
      const { postToIOS } = await import('./iosMessaging')
      postToIOS('updateUI', { type: 'ready' })

      // Assert
      expect(mockPostMessage).toHaveBeenCalledWith(JSON.stringify({ type: 'ready' }))
    })

    it('should not throw when handler does not exist', async () => {
      // Arrange
      // @ts-expect-error - mocking webkit for testing
      window.webkit = {
        messageHandlers: {},
      }

      // Act & Assert
      const { postToIOS } = await import('./iosMessaging')
      expect(() => postToIOS('nonExistentHandler', { test: true })).not.toThrow()
    })

    it('should not throw when window.webkit is undefined (development mode)', async () => {
      // Arrange: window.webkit is deleted in beforeEach

      // Act & Assert
      const { postToIOS } = await import('./iosMessaging')
      expect(() => postToIOS('updateUI', { test: true })).not.toThrow()
    })

    it('should log to console in development mode when not in iOS WebView', async () => {
      // Arrange
      const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {})

      // Act
      const { postToIOS } = await import('./iosMessaging')
      postToIOS('updateUI', { type: 'test' })

      // Assert
      expect(consoleSpy).toHaveBeenCalledWith(
        '[postToIOS] updateUI:',
        expect.any(String)
      )
      consoleSpy.mockRestore()
    })

    it('should serialize message as JSON string', async () => {
      // Arrange
      const mockPostMessage = vi.fn()
      // @ts-expect-error - mocking webkit for testing
      window.webkit = {
        messageHandlers: {
          locationChange: { postMessage: mockPostMessage },
        },
      }
      const message = { mm: [1.5, 2.5, 3.5], voxel: [10, 20, 30] }

      // Act
      const { postToIOS } = await import('./iosMessaging')
      postToIOS('locationChange', message)

      // Assert
      expect(mockPostMessage).toHaveBeenCalledWith(JSON.stringify(message))
    })
  })

  describe('MessageHandler types', () => {
    it('should support updateUI handler', async () => {
      const mockPostMessage = vi.fn()
      // @ts-expect-error - mocking webkit for testing
      window.webkit = {
        messageHandlers: {
          updateUI: { postMessage: mockPostMessage },
        },
      }

      const { postToIOS } = await import('./iosMessaging')
      postToIOS('updateUI', { ready: true })

      expect(mockPostMessage).toHaveBeenCalled()
    })

    it('should support logMessage handler', async () => {
      const mockPostMessage = vi.fn()
      // @ts-expect-error - mocking webkit for testing
      window.webkit = {
        messageHandlers: {
          logMessage: { postMessage: mockPostMessage },
        },
      }

      const { postToIOS } = await import('./iosMessaging')
      postToIOS('logMessage', { level: 'debug', message: 'test' })

      expect(mockPostMessage).toHaveBeenCalled()
    })

    it('should support locationChange handler', async () => {
      const mockPostMessage = vi.fn()
      // @ts-expect-error - mocking webkit for testing
      window.webkit = {
        messageHandlers: {
          locationChange: { postMessage: mockPostMessage },
        },
      }

      const { postToIOS } = await import('./iosMessaging')
      postToIOS('locationChange', { mm: [0, 0, 0] })

      expect(mockPostMessage).toHaveBeenCalled()
    })
  })
})
