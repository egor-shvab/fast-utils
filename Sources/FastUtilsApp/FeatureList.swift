import Core
import FeatureClipboard
import FeatureColor
import FeatureOCR
import FeatureScreenshot
import FeatureText
import FeatureTranslate

/// All feature modules, in menu order. Adding a feature = one line here.
@MainActor
let featureTypes: [any Feature.Type] = [
    OCRFeature.self,
    TranslateFeature.self,
    ClipboardFeature.self,
    TextFeature.self,
    ColorFeature.self,
    ScreenshotFeature.self,
]
