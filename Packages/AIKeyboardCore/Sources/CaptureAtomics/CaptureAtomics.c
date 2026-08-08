// Everything in this target is a static inline function in
// `include/CaptureAtomics.h`. SwiftPM will not build a target with no source
// file, so this one exists to give it one.
#include "CaptureAtomics.h"
