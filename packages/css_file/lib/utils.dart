import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';

typedef CheckIsTargetType = bool Function(ElementAnnotation meta);

// NOTE:
// AI Chat 說:
// - `TypeChecker` 比文字比對好, 還能比對來源路徑.
// - 本方法是 `TypeChecker.firstAnnotationOfExact()` 的底層調用方法.
//
//
// 文字比對方法:
//
// ```dart
// final constantType = meta.computeConstantValue()?.type?.element?.name;
// final enclosingName = meta.element?.enclosingElement?.name;
// final elementName = meta.element?.name;
// return constantType == 'CssFile' || elementName == 'CssFile' || enclosingName == 'CssFile';
// ```

/// 創建過濾註解類型的函式.
/// 可以濾註直接的註解實例化 (`@CssFile()`) 和賦值給變數的宣告
/// (`@cssfile` 來源於 `var cssfile = CssFile()`).
///
/// 範例:
///
/// ```dart
/// final checkCssFileType = createTypeChecker(
///   CssFile,
///   inPackage: 'jaspr_css_file_builder',
/// );
///
/// // 檢查是否存在 @CssFile 註解
/// annotations.any(checkCssFileType);
///
/// // 取得 @CssFile 註解
/// annotations.firstWhere(checkCssFileType);
/// ```
CheckIsTargetType createTypeChecker(Type target, {String? inPackage}) {
  final typeChecker = TypeChecker.typeNamed(target, inPackage: inPackage);
  return (ElementAnnotation meta) {
    // 透過 constantValue 或是 element 進行安全檢查
    final annotationElement = meta.element;
    if (annotationElement == null) return false;

    if (typeChecker.isExactly(annotationElement)) return true;

    final computedType = meta.computeConstantValue()?.type;
    return computedType != null && typeChecker.isExactlyType(computedType);
  };
}
