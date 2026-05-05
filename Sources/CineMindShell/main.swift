import Domain
import Persistence
import Scanner
import Shared

let linkedModules = [
    CineMindBuildInfo.productName,
    CineMindBuildInfo.phaseName,
    String(describing: Library.self),
    String(describing: CineMindStore.self),
    String(describing: LibraryScanner.self)
]

print(linkedModules.joined(separator: " | "))
