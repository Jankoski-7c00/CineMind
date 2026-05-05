import Domain
import Persistence
import Scanner
import Shared

let linkedTypes: [Any.Type] = [
    Library.self,
    CineMindStore.self,
    LibraryScanner.self
]
_ = linkedTypes

let availableModules = ["Shared", "Domain", "Persistence", "Scanner"]

print(CineMindBuildInfo.productName)
print(CineMindBuildInfo.phaseName)
print("Available modules: \(availableModules.joined(separator: ", "))")
print("Phase 1 foundation ready")
