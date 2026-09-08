import Foundation

@MainActor
func workingQueueItemEditorLookup<Value>(
    _ operation: () throws -> Value
) throws -> Value? {
    do {
        return try operation()
    } catch WorkingRepositoryError.sessionNotFound {
        return nil
    } catch WorkingRepositoryError.queueItemNotFound {
        return nil
    } catch {
        throw error
    }
}
