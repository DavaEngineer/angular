import 'package:source_span/source_span.dart';

import '../../core/linker/view_type.dart';
import '../expression_parser/ast.dart' as ast;
import '../expression_parser/parser.dart';
import '../output/output_ast.dart' as o;
import '../schema/element_schema_registry.dart';
import '../template_ast.dart';
import '../template_parser.dart';
import "compile_element.dart" show CompileElement;
import "compile_method.dart" show CompileMethod;
import "compile_view.dart" show CompileView;
import "event_binder.dart"
    show
        bindRenderOutputs,
        collectEventListeners,
        CompileEventListener,
        bindDirectiveOutputs;
import 'ir/provider_source.dart';
import "lifecycle_binder.dart"
    show
        bindDirectiveAfterContentLifecycleCallbacks,
        bindDirectiveAfterViewLifecycleCallbacks,
        bindDirectiveDestroyLifecycleCallbacks,
        bindPipeDestroyLifecycleCallbacks,
        bindDirectiveDetectChangesLifecycleCallbacks;
import "property_binder.dart"
    show
        bindAndWriteToRenderer,
        bindDirectiveHostProps,
        bindDirectiveInputs,
        bindInlinedNgIf,
        bindRenderInputs,
        bindRenderText;

/// Visits view nodes to generate code for bindings.
///
/// Called by ViewCompiler for each top level CompileView and the
/// ViewBinderVisitor recursively for each embedded template.
void bindView(CompileView view, List<TemplateAst> parsedTemplate) {
  var visitor = _ViewBinderVisitor(view);
  templateVisitAll(visitor, parsedTemplate);
  for (var pipe in view.pipes) {
    bindPipeDestroyLifecycleCallbacks(pipe.meta, pipe.instance, pipe.view);
  }
}

class _ViewBinderVisitor implements TemplateAstVisitor<void, dynamic> {
  final CompileView view;
  int _nodeIndex = 0;
  _ViewBinderVisitor(this.view);

  void visitBoundText(BoundTextAst ast, dynamic context) {
    var node = this.view.nodes[_nodeIndex++];
    bindRenderText(ast, node, this.view);
  }

  void visitText(TextAst ast, dynamic context) {
    _nodeIndex++;
  }

  @override
  void visitNgContainer(NgContainerAst ast, dynamic context) {
    templateVisitAll(this, ast.children);
  }

  void visitNgContent(NgContentAst ast, dynamic context) {}

  void visitElement(ElementAst ast, dynamic context) {
    var compileElement = (view.nodes[_nodeIndex++] as CompileElement);
    var listeners = collectEventListeners(ast.outputs, ast.directives,
        compileElement, view.component.analyzedClass);

    // Collect directive output names.
    final directiveOutputs = Set<String>();
    for (var directiveAst in ast.directives) {
      directiveOutputs.addAll(directiveAst.directive.outputs.values);
    }

    // Determine which listeners must be registered as stream subscriptions,
    // and which must be registered as event handlers.
    final eventListeners = <CompileEventListener>[];
    final streamListeners = <CompileEventListener>[];
    for (var listener in listeners) {
      if (directiveOutputs.contains(listener.eventName)) {
        streamListeners.add(listener);
      } else {
        eventListeners.add(listener);
      }
    }

    bindRenderInputs(ast.inputs, compileElement);
    bindRenderOutputs(eventListeners);
    var index = -1;
    for (var directiveAst in ast.directives) {
      index++;
      ProviderSource s = compileElement.directiveInstances[index];
      // Skip functional directives.
      if (s == null) continue;
      var directiveInstance = s.build();
      if (directiveInstance == null) continue;
      bindDirectiveInputs(directiveAst, directiveInstance, compileElement,
          isHostComponent: compileElement.view.viewType == ViewType.host);
      bindDirectiveDetectChangesLifecycleCallbacks(
          directiveAst, directiveInstance, compileElement);
      bindDirectiveHostProps(directiveAst, directiveInstance, compileElement);
      bindDirectiveOutputs(directiveAst, directiveInstance, streamListeners);
    }
    templateVisitAll(this, ast.children, compileElement);
    // afterContent and afterView lifecycles need to be called bottom up
    // so that children are notified before parents
    index = -1;
    for (var directiveAst in ast.directives) {
      index++;
      ProviderSource s = compileElement.directiveInstances[index];
      // Skip functional directives.
      if (s == null) continue;
      var directiveInstance = s.build();
      if (directiveInstance == null) continue;
      bindDirectiveAfterContentLifecycleCallbacks(
          directiveAst.directive, directiveInstance, compileElement);
      bindDirectiveAfterViewLifecycleCallbacks(
          directiveAst.directive, directiveInstance, compileElement);
      bindDirectiveDestroyLifecycleCallbacks(
          directiveAst.directive, directiveInstance, compileElement);
    }
  }

  void visitEmbeddedTemplate(EmbeddedTemplateAst ast, dynamic context) {
    var compileElement = this.view.nodes[this._nodeIndex++] as CompileElement;
    if (compileElement.embeddedView.isInlined) {
      visitInlinedTemplate(ast, compileElement);
      return;
    }
    // The template parser ensures these listeners are for directive outputs,
    // so they all must be registered as stream subscriptions.
    var eventListeners = collectEventListeners(ast.outputs, ast.directives,
        compileElement, view.component.analyzedClass);
    var index = -1;
    for (var directiveAst in ast.directives) {
      index++;
      ProviderSource s = compileElement.directiveInstances[index];
      // Skip functional directives.
      if (s == null) continue;
      var directiveInstance = s.build();
      if (directiveInstance == null) continue;
      bindDirectiveInputs(directiveAst, directiveInstance, compileElement);
      bindDirectiveDetectChangesLifecycleCallbacks(
          directiveAst, directiveInstance, compileElement);
      bindDirectiveOutputs(directiveAst, directiveInstance, eventListeners);
      bindDirectiveAfterContentLifecycleCallbacks(
          directiveAst.directive, directiveInstance, compileElement);
      bindDirectiveAfterViewLifecycleCallbacks(
          directiveAst.directive, directiveInstance, compileElement);
      bindDirectiveDestroyLifecycleCallbacks(
          directiveAst.directive, directiveInstance, compileElement);
    }
    bindView(compileElement.embeddedView, ast.children);
  }

  void visitInlinedTemplate(
      EmbeddedTemplateAst ast, CompileElement compileElement) {
    var directiveAst = ast.directives.single;
    if (ast.children.isEmpty) {
      return;
    }
    bindInlinedNgIf(directiveAst, compileElement);
  }

  void visitAttr(AttrAst ast, dynamic context) {}

  void visitDirective(DirectiveAst ast, dynamic context) {}

  void visitEvent(BoundEventAst ast, dynamic context) {
    var eventTargetAndNames = context as Map<String, BoundEventAst>;
    assert(eventTargetAndNames != null);
  }

  void visitReference(ReferenceAst ast, dynamic context) {}

  void visitVariable(VariableAst ast, dynamic context) {}

  void visitDirectiveProperty(BoundDirectivePropertyAst ast, dynamic context) {}

  void visitElementProperty(BoundElementPropertyAst ast, dynamic context) {}

  void visitProvider(ProviderAst ast, dynamic context) {}

  void visitI18nText(I18nTextAst ast, dynamic context) {
    _nodeIndex++;
  }
}

void bindViewHostProperties(CompileView view, Parser parser,
    ElementSchemaRegistry schemaRegistry, ErrorCallback errorCallback) {
  if (view.viewIndex != 0 || view.viewType != ViewType.component) return;
  var hostProps = view.component.hostProperties;
  if (hostProps == null) return;

  List<BoundElementPropertyAst> hostProperties = <BoundElementPropertyAst>[];

  var span = SourceSpan(SourceLocation(0), SourceLocation(0), '');
  hostProps.forEach((String propName, ast.AST expression) {
    var elementName = view.component.selector;
    hostProperties.add(createElementPropertyAst(elementName, propName,
        expression, span, schemaRegistry, errorCallback));
  });

  final CompileMethod method = CompileMethod();
  var compileElement = view.componentView.declarationElement;
  var renderNode = view.componentView.declarationElement.renderNode;
  bindAndWriteToRenderer(
      hostProperties,
      o.THIS_EXPR,
      o.ReadClassMemberExpr('ctx'),
      view.component,
      renderNode.toReadExpr(),
      compileElement.isHtmlElement,
      view.nameResolver,
      view.storage,
      method,
      updatingHostAttribute: true);
  if (method.isNotEmpty) {
    view.detectHostChangesMethod = method;
  }
}
