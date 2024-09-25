import 'package:attributed_text/attributed_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/core/styles.dart';
import 'package:super_editor/src/default_editor/blocks/indentation.dart';
import 'package:super_editor/src/default_editor/multi_node_editing.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/attributed_text_styles.dart';
import 'package:super_editor/src/infrastructure/composable_text.dart';
import 'package:super_editor/src/infrastructure/keyboard.dart';
import 'package:super_text_layout/super_text_layout.dart';

import 'attributions.dart';
import 'layout_single_column/layout_single_column.dart';

/// This file includes everything needed to add the concept of a task
/// to Super Editor. This includes:
///
///  * [TaskNode], which represents a logical task.
///  * [TaskComponentViewModel], which configures the visual appearance
///    of a task in a document.
///  * [taskStyles], which applies desired styles to tasks in a document.
///  * [TaskComponentBuilder], which creates new [TaskComponentViewModel]s
///    and [TaskComponent]s, for every [TaskNode] in the document.
///  * [TaskComponent], which renders a task in a document.

/// [DocumentNode] that represents a task to complete.
///
/// A task can either be complete, or incomplete.
class TaskNode extends TextNode {
  TaskNode({
    required String id,
    required AttributedText text,
    Map<String, dynamic>? metadata,
    required bool isComplete,
    int indent = 0,
  })  : _isComplete = isComplete,
        _indent = indent,
        super(id: id, text: text, metadata: metadata) {
    // Set a block type so that TaskNode's can be styled by
    // StyleRule's.
    putMetadataValue("blockType", const NamedAttribution("task"));
  }

  /// Whether this task is complete.
  bool get isComplete => _isComplete;
  bool _isComplete;
  set isComplete(bool newValue) {
    if (newValue == _isComplete) {
      return;
    }

    _isComplete = newValue;
    notifyListeners();
  }

  /// The indent level of this task - `0` is no indent.
  ///
  /// A task can only be indented one level beyond its parent task.
  int get indent => _indent;
  int _indent;
  set indent(int newValue) {
    if (newValue == _indent) {
      return;
    }

    _indent = newValue;
    notifyListeners();
  }

  @override
  bool hasEquivalentContent(DocumentNode other) {
    return other is TaskNode && isComplete == other.isComplete && text == other.text;
  }

  @override
  TaskNode copy() {
    return TaskNode(
      id: id,
      text: text.copyText(0),
      metadata: Map.from(metadata),
      isComplete: isComplete,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TaskNode &&
          runtimeType == other.runtimeType &&
          isComplete == other.isComplete &&
          indent == other.indent;

  @override
  int get hashCode => super.hashCode ^ isComplete.hashCode ^ indent.hashCode;
}

/// Styles all task components to apply top padding
final taskStyles = StyleRule(
  const BlockSelector("task"),
  (document, node) {
    if (node is! TaskNode) {
      return {};
    }

    return {
      Styles.padding: const CascadingPadding.only(top: 24),
    };
  },
);

/// Builds [TaskComponentViewModel]s and [TaskComponent]s for every
/// [TaskNode] in a document.
class TaskComponentBuilder implements ComponentBuilder {
  TaskComponentBuilder(this._editor);

  final Editor _editor;

  @override
  TaskComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! TaskNode) {
      return null;
    }

    return TaskComponentViewModel(
      nodeId: node.id,
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) {
        _editor.execute([
          ChangeTaskCompletionRequest(
            nodeId: node.id,
            isComplete: isComplete,
          ),
        ]);
      },
      text: node.text,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
      spellingErrors: node.text
          .getAttributionSpansByFilter((a) => a == spellingErrorAttribution)
          .map((a) => TextRange(start: a.start, end: a.end + 1)) // +1 because text range end is exclusive
          .toList(),
    );
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! TaskComponentViewModel) {
      return null;
    }

    return TaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
    );
  }
}

/// View model that configures the appearance of a [TaskComponent].
///
/// View models move through various style phases, which fill out
/// various properties in the view model. For example, one phase applies
/// all [StyleRule]s, and another phase configures content selection
/// and caret appearance.
class TaskComponentViewModel extends SingleColumnLayoutComponentViewModel with TextComponentViewModel {
  TaskComponentViewModel({
    required String nodeId,
    double? maxWidth,
    required EdgeInsetsGeometry padding,
    this.indent = 0,
    this.indentCalculator = defaultTaskIndentCalculator,
    required this.isComplete,
    required this.setComplete,
    required this.text,
    required this.textStyleBuilder,
    this.textDirection = TextDirection.ltr,
    this.textAlignment = TextAlign.left,
    this.selection,
    required this.selectionColor,
    this.highlightWhenEmpty = false,
    TextRange? composingRegion,
    bool showComposingRegionUnderline = false,
    UnderlineStyle spellingErrorUnderlineStyle = const SquiggleUnderlineStyle(color: Color(0xFFFF0000)),
    List<TextRange> spellingErrors = const <TextRange>[],
  }) : super(nodeId: nodeId, maxWidth: maxWidth, padding: padding) {
    this.composingRegion = composingRegion;
    this.showComposingRegionUnderline = showComposingRegionUnderline;

    this.spellingErrorUnderlineStyle = spellingErrorUnderlineStyle;
    this.spellingErrors = spellingErrors;
  }

  int indent;
  TextBlockIndentCalculator indentCalculator;

  bool isComplete;
  void Function(bool) setComplete;

  @override
  AttributedText text;
  @override
  AttributionStyleBuilder textStyleBuilder;
  @override
  TextDirection textDirection;
  @override
  TextAlign textAlignment;
  @override
  TextSelection? selection;
  @override
  Color selectionColor;
  @override
  bool highlightWhenEmpty;

  @override
  TaskComponentViewModel copy() {
    return TaskComponentViewModel(
      nodeId: nodeId,
      maxWidth: maxWidth,
      padding: padding,
      indent: indent,
      indentCalculator: indentCalculator,
      isComplete: isComplete,
      setComplete: setComplete,
      text: text,
      textStyleBuilder: textStyleBuilder,
      textDirection: textDirection,
      selection: selection,
      selectionColor: selectionColor,
      highlightWhenEmpty: highlightWhenEmpty,
      spellingErrorUnderlineStyle: spellingErrorUnderlineStyle,
      spellingErrors: List.from(spellingErrors),
      composingRegion: composingRegion,
      showComposingRegionUnderline: showComposingRegionUnderline,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TaskComponentViewModel &&
          runtimeType == other.runtimeType &&
          indent == other.indent &&
          isComplete == other.isComplete &&
          text == other.text &&
          textDirection == other.textDirection &&
          textAlignment == other.textAlignment &&
          selection == other.selection &&
          selectionColor == other.selectionColor &&
          highlightWhenEmpty == other.highlightWhenEmpty &&
          spellingErrorUnderlineStyle == other.spellingErrorUnderlineStyle &&
          const DeepCollectionEquality().equals(spellingErrors, other.spellingErrors) &&
          composingRegion == other.composingRegion &&
          showComposingRegionUnderline == other.showComposingRegionUnderline;

  @override
  int get hashCode =>
      super.hashCode ^
      indent.hashCode ^
      isComplete.hashCode ^
      text.hashCode ^
      textDirection.hashCode ^
      textAlignment.hashCode ^
      selection.hashCode ^
      selectionColor.hashCode ^
      highlightWhenEmpty.hashCode ^
      spellingErrorUnderlineStyle.hashCode ^
      spellingErrors.hashCode ^
      composingRegion.hashCode ^
      showComposingRegionUnderline.hashCode;
}

/// The standard [TextBlockIndentCalculator] used by tasks in `SuperEditor`.
double defaultTaskIndentCalculator(TextStyle textStyle, int indent) {
  return (textStyle.fontSize! * 0.60) * 4 * indent;
}

/// A document component that displays a complete-able task.
///
/// This is the widget that appears in the document layout for
/// an individual task. This widget includes a checkbox that the
/// user can tap to toggle the completeness of the task.
///
/// The appearance of a [TaskComponent] is configured by the given
/// [viewModel].
class TaskComponent extends StatefulWidget {
  const TaskComponent({
    Key? key,
    required this.viewModel,
    this.showDebugPaint = false,
  }) : super(key: key);

  final TaskComponentViewModel viewModel;
  final bool showDebugPaint;

  @override
  State<TaskComponent> createState() => _TaskComponentState();
}

class _TaskComponentState extends State<TaskComponent> with ProxyDocumentComponent<TaskComponent>, ProxyTextComposable {
  final _textKey = GlobalKey();

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable => childDocumentComponentKey.currentState as TextComposable;

  /// Computes the [TextStyle] for this task's inner [TextComponent].
  TextStyle _computeStyles(Set<Attribution> attributions) {
    // Show a strikethrough across the entire task if it's complete.
    final style = widget.viewModel.textStyleBuilder(attributions);
    return widget.viewModel.isComplete
        ? style.copyWith(
            decoration: style.decoration == null
                ? TextDecoration.lineThrough
                : TextDecoration.combine([TextDecoration.lineThrough, style.decoration!]),
          )
        : style;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: widget.viewModel.indentCalculator(
            widget.viewModel.textStyleBuilder({}),
            widget.viewModel.indent,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Checkbox(
            value: widget.viewModel.isComplete,
            onChanged: (newValue) {
              widget.viewModel.setComplete(newValue!);
            },
          ),
        ),
        Expanded(
          child: TextComponent(
            key: _textKey,
            text: widget.viewModel.text,
            textStyleBuilder: _computeStyles,
            textSelection: widget.viewModel.selection,
            selectionColor: widget.viewModel.selectionColor,
            highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
            underlines: widget.viewModel.createUnderlines(),
            showDebugPaint: widget.showDebugPaint,
          ),
        ),
      ],
    );
  }
}

ExecutionInstruction enterToInsertNewTask({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  // We only care about ENTER.
  if (keyEvent.logicalKey != LogicalKeyboardKey.enter && keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return ExecutionInstruction.continueExecution;
  }

  // We only care when the selection is collapsed to a caret.
  final selection = editContext.composer.selection;
  if (selection == null || !selection.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  // We only care about TaskNodes.
  final node = editContext.document.getNodeById(selection.extent.nodeId);
  if (node is! TaskNode) {
    return ExecutionInstruction.continueExecution;
  }

  if (node.text.text.isEmpty) {
    // The task is empty. Convert it to a paragraph.
    editContext.editor.execute([
      ConvertTextNodeToParagraphRequest(nodeId: node.id),
    ]);
    return ExecutionInstruction.haltExecution;
  }

  final splitOffset = (selection.extent.nodePosition as TextNodePosition).offset;

  editContext.editor.execute([
    SplitExistingTaskRequest(
      existingNodeId: node.id,
      splitOffset: splitOffset,
    ),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction backspaceToConvertTaskToParagraph({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (!editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! TaskNode) {
    return ExecutionInstruction.continueExecution;
  }

  if ((editContext.composer.selection!.extent.nodePosition as TextPosition).offset > 0) {
    // The selection isn't at the beginning.
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    DeleteUpstreamAtBeginningOfNodeRequest(node),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction tabToIndentTask({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.tab) {
    return ExecutionInstruction.continueExecution;
  }

  if (HardwareKeyboard.instance.isShiftPressed) {
    // Don't indent if Shift is pressed - that's for un-indenting.
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (selection.base.nodeId != selection.extent.nodeId) {
    // Selection spans nodes, so even if this selection includes a task,
    // it includes other stuff, too. So we can't treat this as a task indentation.
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! TaskNode) {
    return ExecutionInstruction.continueExecution;
  }

  final nodeIndex = editContext.document.getNodeIndexById(node.id);
  if (nodeIndex == 0) {
    // No task above us, so we can't indent.
    return ExecutionInstruction.continueExecution;
  }
  final taskAbove = editContext.document.getNodeAt(nodeIndex - 1);
  if (taskAbove is! TaskNode) {
    // The node above isn't a task. We can't indent.
    return ExecutionInstruction.continueExecution;
  }

  final maxIndent = taskAbove.indent + 1;
  if (node.indent >= maxIndent) {
    // Can't indent any further.
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    IndentTaskRequest(node.id),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction shiftTabToUnIndentTask({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.tab) {
    return ExecutionInstruction.continueExecution;
  }
  if (!HardwareKeyboard.instance.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (selection.base.nodeId != selection.extent.nodeId) {
    // Selection spans nodes, so even if this selection includes a task,
    // it includes other stuff, too. So we can't treat this as a task indentation.
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! TaskNode) {
    return ExecutionInstruction.continueExecution;
  }

  if (node.indent == 0) {
    // Can't un-indent any further.
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    UnIndentTaskRequest(node.id),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction backspaceToUnIndentTask({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (selection.base.nodeId != selection.extent.nodeId) {
    // Selection spans nodes, so even if this selection includes a task,
    // it includes other stuff, too. So we can't treat this as a task indentation.
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! TaskNode) {
    return ExecutionInstruction.continueExecution;
  }
  if ((editContext.composer.selection!.extent.nodePosition as TextPosition).offset > 0) {
    // Backspace should only un-indent if the caret is at the start of the text.
    return ExecutionInstruction.continueExecution;
  }

  if (node.indent == 0) {
    // Can't un-indent any further.
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    UnIndentTaskRequest(node.id),
  ]);

  return ExecutionInstruction.haltExecution;
}

class ChangeTaskCompletionRequest implements EditRequest {
  ChangeTaskCompletionRequest({required this.nodeId, required this.isComplete});

  final String nodeId;
  final bool isComplete;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangeTaskCompletionRequest &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          isComplete == other.isComplete;

  @override
  int get hashCode => nodeId.hashCode ^ isComplete.hashCode;
}

class ChangeTaskCompletionCommand extends EditCommand {
  ChangeTaskCompletionCommand({required this.nodeId, required this.isComplete});

  final String nodeId;
  final bool isComplete;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final taskNode = context.document.getNodeById(nodeId);
    if (taskNode is! TaskNode) {
      return;
    }

    taskNode.isComplete = isComplete;

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(nodeId),
      ),
    ]);
  }
}

class ConvertParagraphToTaskRequest implements EditRequest {
  const ConvertParagraphToTaskRequest({
    required this.nodeId,
    this.isComplete = false,
  });

  final String nodeId;
  final bool isComplete;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConvertParagraphToTaskRequest &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          isComplete == other.isComplete;

  @override
  int get hashCode => nodeId.hashCode ^ isComplete.hashCode;
}

class ConvertParagraphToTaskCommand extends EditCommand {
  const ConvertParagraphToTaskCommand({
    required this.nodeId,
    this.isComplete = false,
  });

  final String nodeId;
  final bool isComplete;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final existingNode = document.getNodeById(nodeId);
    if (existingNode is! ParagraphNode) {
      editorOpsLog.warning(
          "Tried to convert ParagraphNode with ID '$nodeId' to TaskNode, but that node has the wrong type: ${existingNode.runtimeType}");
      return;
    }

    final taskNode = TaskNode(
      id: existingNode.id,
      text: existingNode.text,
      isComplete: isComplete,
    );

    executor.executeCommand(
      ReplaceNodeCommand(existingNodeId: existingNode.id, newNode: taskNode),
    );
  }
}

class ConvertTaskToParagraphRequest implements EditRequest {
  const ConvertTaskToParagraphRequest({
    required this.nodeId,
    this.paragraphMetadata,
  });

  final String nodeId;
  final Map<String, dynamic>? paragraphMetadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConvertTaskToParagraphRequest &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          paragraphMetadata == other.paragraphMetadata;

  @override
  int get hashCode => nodeId.hashCode ^ paragraphMetadata.hashCode;
}

class ConvertTaskToParagraphCommand extends EditCommand {
  const ConvertTaskToParagraphCommand({
    required this.nodeId,
    this.paragraphMetadata,
  });

  final String nodeId;
  final Map<String, dynamic>? paragraphMetadata;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final node = document.getNodeById(nodeId);
    final taskNode = node as TaskNode;
    final newMetadata = Map<String, dynamic>.from(paragraphMetadata ?? {});
    newMetadata["blockType"] = paragraphAttribution;

    final newParagraphNode = ParagraphNode(
      id: taskNode.id,
      text: taskNode.text,
      metadata: newMetadata,
    );
    document.replaceNode(oldNode: taskNode, newNode: newParagraphNode);

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(taskNode.id),
      )
    ]);
  }
}

class SplitExistingTaskRequest implements EditRequest {
  const SplitExistingTaskRequest({
    required this.existingNodeId,
    required this.splitOffset,
    this.newNodeId,
  });

  final String existingNodeId;
  final int splitOffset;
  final String? newNodeId;
}

class SplitExistingTaskCommand extends EditCommand {
  const SplitExistingTaskCommand({
    required this.nodeId,
    required this.splitOffset,
    this.newNodeId,
  });

  final String nodeId;
  final int splitOffset;
  final String? newNodeId;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext editContext, CommandExecutor executor) {
    final document = editContext.document;
    final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;

    // We only care when the caret sits at the end of a TaskNode.
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    // We only care about TaskNodes.
    final node = document.getNodeById(selection.extent.nodeId);
    if (node is! TaskNode) {
      return;
    }

    // Ensure the split offset is valid.
    if (splitOffset < 0 || splitOffset > node.text.length + 1) {
      return;
    }

    final newTaskNode = TaskNode(
      id: newNodeId ?? Editor.createNodeId(),
      text: node.text.copyText(splitOffset),
      isComplete: false,
      indent: node.indent,
    );

    // Remove the text after the caret from the currently selected TaskNode.
    node.text = node.text.removeRegion(startOffset: splitOffset, endOffset: node.text.length);

    // Insert a new TextNode after the currently selected TaskNode.
    document.insertNodeAfter(existingNode: node, newNode: newTaskNode);

    // Move the caret to the beginning of the new TaskNode.
    final oldSelection = composer.selection;
    final oldComposingRegion = composer.composingRegion.value;
    final newSelection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: newTaskNode.id,
        nodePosition: const TextNodePosition(offset: 0),
      ),
    );

    composer.setSelectionWithReason(newSelection, SelectionReason.userInteraction);
    composer.setComposingRegion(null);

    executor.logChanges([
      SplitTaskIntention.start(),
      DocumentEdit(
        NodeChangeEvent(node.id),
      ),
      DocumentEdit(
        NodeInsertedEvent(newTaskNode.id, document.getNodeIndexById(newTaskNode.id)),
      ),
      SelectionChangeEvent(
        oldSelection: oldSelection,
        newSelection: newSelection,
        changeType: SelectionChangeType.pushCaret,
        reason: SelectionReason.userInteraction,
      ),
      ComposingRegionChangeEvent(
        oldComposingRegion: oldComposingRegion,
        newComposingRegion: null,
      ),
      SplitTaskIntention.end(),
    ]);
  }
}

class SplitTaskIntention extends Intention {
  SplitTaskIntention.start() : super.start();

  SplitTaskIntention.end() : super.end();
}

class IndentTaskRequest implements EditRequest {
  const IndentTaskRequest(this.nodeId);

  final String nodeId;
}

class IndentTaskCommand extends EditCommand {
  const IndentTaskCommand(this.nodeId);

  final String nodeId;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final task = document.getNodeById(nodeId);
    if (task is! TaskNode) {
      // The specified node isn't a task. Nothing for us to indent.
      return;
    }

    if (task.indent >= 6) {
      return;
    }

    // Increase the task indentation.
    task.indent += 1;

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(task.id),
      ),
    ]);
  }
}

class UnIndentTaskRequest implements EditRequest {
  const UnIndentTaskRequest(this.nodeId);

  final String nodeId;
}

class UnIndentTaskCommand extends EditCommand {
  const UnIndentTaskCommand(this.nodeId);

  final String nodeId;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final task = document.getNodeById(nodeId);
    if (task is! TaskNode) {
      // The specified node isn't a task. Nothing for us to indent.
      return;
    }

    if (task.indent == 0) {
      // This task is already at minimum indent. Nothing to do.
      return;
    }

    final subTasks = <TaskNode>[];
    int index = document.getNodeIndexById(task.id) + 1;
    while (index < document.nodeCount) {
      final subTask = document.getNodeAt(index);
      if (subTask is! TaskNode) {
        break;
      }
      if (subTask.indent <= task.indent) {
        break;
      }

      subTasks.add(subTask);
      index += 1;
    }

    final changeLog = <DocumentEdit>[];

    // Decrease the task indentation of the desired task.
    task.indent -= 1;
    changeLog.add(
      DocumentEdit(
        NodeChangeEvent(task.id),
      ),
    );

    // Decrease the indentation of the sub-tasks.
    for (final subTask in subTasks) {
      subTask.indent -= 1;
      changeLog.add(
        DocumentEdit(
          NodeChangeEvent(subTask.id),
        ),
      );
    }

    // Log all changes.
    executor.logChanges(changeLog);
  }
}

/// Sets the indent of the task with ID [nodeId] to the given [indent].
///
/// This request doesn't verify any rules about allowed indentation
/// levels. It blindly applies the indent. Therefore, this request should
/// only be issued from places that have already validated the result.
class SetTaskIndentRequest implements EditRequest {
  const SetTaskIndentRequest(this.nodeId, this.indent);

  final String nodeId;
  final int indent;
}

class SetTaskIndentCommand extends EditCommand {
  const SetTaskIndentCommand(this.nodeId, this.indent);

  final String nodeId;
  final int indent;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final task = document.getNodeById(nodeId);
    if (task is! TaskNode) {
      // The specified node isn't a task. Nothing for us to indent.
      return;
    }

    task.indent = indent;
    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(task.id),
      ),
    ]);
  }
}

class UpdateSubTaskIndentAfterTaskDeletionReaction extends EditReaction {
  @override
  void modifyContent(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final didDeleteTask = changeList
        .whereType<DocumentEdit>()
        .where((edit) => edit.change is NodeRemovedEvent && (edit.change as NodeRemovedEvent).removedNode is TaskNode)
        .isNotEmpty;
    if (!didDeleteTask) {
      // No tasks were deleted, so there are no task indentations to fix.
      return;
    }

    // At least one task was deleted. We're not sure where in the document the
    // tasks were before being deleted. Therefore, we check and fix every task
    // indentation in the document.
    final document = editorContext.document;
    final changeIndentationRequests = <EditRequest>[];
    int maxIndentation = 0;
    for (int i = 0; i < document.nodeCount; i += 1) {
      final node = document.getNodeAt(i);
      if (node is! TaskNode) {
        // This node isn't a task. The first task in a list of tasks
        // can't have an indent, so reset the max indent back to zero.
        maxIndentation = 0;
        continue;
      }

      if (node.indent > maxIndentation) {
        // This task has an indent that's too deep. Fix it by
        // settings its indent to the max allowed.
        changeIndentationRequests.add(
          SetTaskIndentRequest(node.id, maxIndentation),
        );

        // A task that follows this one is allowed (up to) the previous
        // max + 1.
        maxIndentation += 1;
        continue;
      }

      // This is a task with a legitimate indent. Update the
      // max indent tracker based on this task's level.
      maxIndentation = node.indent + 1;
    }

    if (changeIndentationRequests.isEmpty) {
      // No changes needed.
      return;
    }

    // Adjust all tasks with illegal indentations.
    requestDispatcher.execute(changeIndentationRequests);
  }
}
