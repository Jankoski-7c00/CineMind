import Application
import LibMPVPlayback
import Playback
import Shared

let availableModules: [Any.Type] = [
    ApplicationModule.self,
    PlaybackModule.self,
    LibMPVPlaybackModule.self
]

_ = availableModules

print(CineMindBuildInfo.productName)
print("Phase 2 Playback MVP")
print("Available modules: Application, Playback, LibMPVPlayback")
print("Phase 2 playback topology ready")
