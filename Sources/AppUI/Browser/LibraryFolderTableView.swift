import Application
import SwiftUI

struct LibraryFolderTableView: View {
    let folders: [LibraryFolderSummary]

    var body: some View {
        Table(of: LibraryFolderSummary.self) {
            TableColumn("Name") { folder in
                Text(folder.displayName)
            }
            TableColumn("Path") { folder in
                Text(folder.rootPath)
            }
            TableColumn("Availability") { folder in
                LibraryBrowserStatusLabel(
                    descriptor: LibraryBrowserStatusPresentation.availability(folder.availabilityLabel)
                )
            }
            TableColumn("Files") { folder in
                Text(folder.fileCountLabel)
            }
            TableColumn("Last Seen") { folder in
                Text(folder.lastSeenLabel ?? CineMindDisplayText.emptyValue)
            }
            TableColumn("Last Scan") { folder in
                Text(folder.lastScanLabel ?? CineMindDisplayText.emptyValue)
            }
        } rows: {
            ForEach(folders) { folder in
                TableRow(folder)
            }
        }
    }
}
