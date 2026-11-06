import Core
import FeatureClipboard
import FeatureOCR
import FeatureText
import FeatureTranslate

/// All feature modules, in menu order. Adding a feature = one line here.
@MainActor
let featureTypes: [any Feature.Type] = [
    OCRFeature.self,
    TranslateFeature.self,
    ClipboardFeature.self,
    TextFeature.self,
]
