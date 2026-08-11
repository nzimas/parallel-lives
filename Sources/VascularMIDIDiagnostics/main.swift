import CoreMIDI
import Foundation

func name(of object: MIDIObjectRef) -> String {
    var value: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &value) == noErr else {
        return "<unnamed>"
    }
    return value?.takeRetainedValue() as String? ?? "<unnamed>"
}

print("MIDI sources:")
for index in 0..<MIDIGetNumberOfSources() {
    let endpoint = MIDIGetSource(index)
    print("  [\(index)] \(name(of: endpoint))")
}

print("MIDI destinations:")
for index in 0..<MIDIGetNumberOfDestinations() {
    let endpoint = MIDIGetDestination(index)
    print("  [\(index)] \(name(of: endpoint))")
}
