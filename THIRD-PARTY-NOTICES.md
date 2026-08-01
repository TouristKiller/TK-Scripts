# Third-Party Notices

The MIT license in [LICENSE](LICENSE) covers the original work in TK Scripts.
Some parts of this repository build on, or ship alongside, code by other
authors. Those parts remain under their own terms, and this file lists what I
am aware of.

If you are reusing code from TK Scripts, everything not listed below is mine
end-to-end and is MIT-licensed.

## TK ChordGun (`Midi/TK_ChordGun/`)

Based on ChordGun by pandabot. My additions (scale library, scale
filter/remap, chord recognition, voice leading, arpeggiator, score and guitar
views, and related changes) are MIT-licensed, but the underlying ChordGun code
is not mine to relicense. Please check the original project's terms before
redistributing this script or derivatives of it.

## REAPER SDK

Some native components vendor the REAPER plug-in SDK (under
`*/build/*/_deps/reaper_sdk-src/`) as a build dependency. The SDK is
distributed by Cockos under its own license; see the `LICENSE` files inside
that directory. It is a dependency, not part of TK Scripts.

## Reporting

If you spot something in this repository that should be credited here and
isn't, please open an issue — it will be an oversight, not an intent, and I'll
fix it.
