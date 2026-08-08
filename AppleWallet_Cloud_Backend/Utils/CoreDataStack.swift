import Foundation
import CoreData

/// CoreData stack для Apple Wallet Clone
/// iOS 26, использует NSPersistentContainer, background contexts, migration
final class CoreDataStack {

    // MARK: - Singleton
    static let shared = CoreDataStack()

    // MARK: - Properties
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "WalletModel")

        // Настройка для iCloud sync
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.wallet.app")

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    var context: NSManagedObjectContext {
        return container.viewContext
    }

    // MARK: - Initialization
    private init() {}

    // MARK: - Context Management

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                AnalyticsCollector.shared.logError(error, context: "CoreDataSave")
            }
        }
    }
}
