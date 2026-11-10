import Testing
import Foundation
@testable import RideKit

@Suite("Watch check-in with the iPhone")
struct InventoryTests {
    @Test func checkInMessagesRoundTripThroughPropertyListDictionaries() {
        let a = UUID(), b = UUID()
        for m in [SyncMessage.inventoryRequest(ids: [a, b]), .inventoryReply(stored: [a], deleted: [b]),
                  .inventoryRequest(ids: []), .inventoryReply(stored: [], deleted: [])] {
            #expect(SyncMessage(dictionary: m.dictionary) == m)
            #expect(PropertyListSerialization.propertyList(m.dictionary, isValidFor: .binary))
        }
    }

    @Test func largestRequestStaysFarBelowTheMessageLimit() throws {
        let ids = (0..<Inventory.maxRequestIDs).map { _ in UUID() }
        let size = try PropertyListSerialization.data(fromPropertyList: SyncMessage.inventoryRequest(ids: ids).dictionary,
                                                      format: .binary, options: 0).count
        #expect(size < 32_000)
    }

    @Test func requestSkipsDeletedRidesKeepsOrderAndIsCapped() {
        let ids = (0..<(Inventory.maxRequestIDs + 20)).map { _ in UUID() }
        var state = SyncState()
        state.deleted = [ids[1]]
        state.acknowledged = [ids[2]]   // acknowledged rides are still asked about, to learn of deletions
        let request = Inventory.requestIDs(stored: ids, state: state)
        #expect(request.count == Inventory.maxRequestIDs)
        #expect(request.first == ids[0])
        #expect(!request.contains(ids[1]))
        #expect(request.contains(ids[2]))
    }

    @Test func iPhoneReplyPutsDeletionAboveAStoredCopy() {
        let stored = UUID(), deletedButPresent = UUID(), deleted = UUID(), unknown = UUID()
        let present: Set<UUID> = [stored, deletedButPresent]
        let reply = Inventory.reply(to: [stored, deletedButPresent, deleted, unknown],
                                    isStored: { present.contains($0) }, deleted: [deletedButPresent, deleted])
        #expect(reply == .inventoryReply(stored: [stored], deleted: [deletedButPresent, deleted]))
    }

    @Test func watchAppliesReplyAndReportsWhatIsMissing() {
        let onPhone = UUID(), alreadyKnown = UUID(), deletedOnPhone = UUID(), notThereYet = UUID(), notAsked = UUID()
        var state = SyncState()
        state.acknowledged = [alreadyKnown, deletedOnPhone]
        let outcome = Inventory.apply(stored: [onPhone, alreadyKnown, notAsked], deleted: [deletedOnPhone, notAsked],
                                      requested: [onPhone, alreadyKnown, deletedOnPhone, notThereYet], to: &state)
        #expect(outcome.newlyAcknowledged == [onPhone])
        #expect(outcome.toDelete == [deletedOnPhone])
        #expect(outcome.missing == [notThereYet])
        #expect(state.acknowledged == [onPhone, alreadyKnown])
        #expect(state.deleted == [deletedOnPhone])
    }

    @Test func applyingTheSameReplyTwiceChangesNothing() {
        let a = UUID(), b = UUID()
        var state = SyncState()
        _ = Inventory.apply(stored: [a], deleted: [b], requested: [a, b], to: &state)
        let before = state
        let again = Inventory.apply(stored: [a], deleted: [b], requested: [a, b], to: &state)
        #expect(state == before)
        #expect(again.newlyAcknowledged.isEmpty)
        #expect(again.toDelete == [b])   // deleting a file that is already gone is harmless
    }
}
