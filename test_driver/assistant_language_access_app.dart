import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/main.dart' as app;
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/providers/theme_provider.dart';
import 'package:uhc/providers/assistant_chat_provider.dart';
import 'package:uhc/screens/patient/assistant/assistant_chat_screen.dart';

// Auth/configuration controls only. Routes, sends and confirmations use real UI.
void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError('QA requires a debug build and isolated demo Firebase.');
  }
  enableFlutterDriverExtension();
  developer.registerExtension('ext.uhc.languageAccess', (_, parameters) async {
    try {
      final context = app.navigatorKey.currentContext!;
      switch (parameters['action']) {
        case 'signIn':
          final ok = await context.read<AuthProvider>().signInWithEmail(
              email: parameters['email']!, password: parameters['password']!);
          if (!ok) throw StateError('Synthetic sign-in failed');
        case 'signOut':
          await context.read<AuthProvider>().signOut();
        case 'environment':
          await context
              .read<LocaleProvider>()
              .setLocaleByCode(parameters['locale'] ?? 'en');
          await context.read<ThemeProvider>().setThemeMode(
              parameters['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light);
        case 'draft':
          final fields = <TextField>[];
          void visit(Element element) {
            if (element.widget is Offstage &&
                (element.widget as Offstage).offstage) {
              return;
            }
            if (element.widget is TextField &&
                element.findAncestorWidgetOfExactType<AssistantChatScreen>() !=
                    null) {
              fields.add(element.widget as TextField);
            }
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          fields.single.controller!.value = TextEditingValue(
            text: parameters['text']!,
            selection:
                TextSelection.collapsed(offset: parameters['text']!.length),
          );
        case 'scrollEnd':
          void visit(Element element) {
            if (element.widget is Offstage &&
                (element.widget as Offstage).offstage) {
              return;
            }
            if (element is StatefulElement &&
                element.state is ScrollableState) {
              final position = (element.state as ScrollableState).position;
              if (position.hasContentDimensions) {
                position.jumpTo(position.maxScrollExtent);
              }
            }
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
        case 'chatState':
          AssistantChatProvider? chat;
          void visit(Element element) {
            if (element.widget is Offstage &&
                (element.widget as Offstage).offstage) {
              return;
            }
            if (element.widget is Consumer<AssistantChatProvider>) {
              chat = element.read<AssistantChatProvider>();
            }
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'status': chat!.currentStatus.name,
            'messages': chat!.messages.length,
            'failure': chat!.failureKind?.name,
            'loading': chat!.isLoading,
            'sending': chat!.isSending,
            'canSend': chat!.canSendMessage,
            'reply': chat!.messages.isEmpty ? null : chat!.messages.last.text,
            'offers': chat!.offers.length,
          }));
        case 'focusReply':
          AssistantChatProvider? chat;
          final paragraphs = <Element>[];
          void visit(Element element) {
            if (element.widget is Offstage &&
                (element.widget as Offstage).offstage) {
              return;
            }
            if (element.widget is Consumer<AssistantChatProvider>) {
              chat = element.read<AssistantChatProvider>();
            }
            if (element.widget is Text &&
                element.findAncestorWidgetOfExactType<AssistantChatScreen>() !=
                    null) {
              paragraphs.add(element);
            }
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          final reply = chat!.messages.last.text;
          final target = paragraphs
              .lastWhere((element) => (element.widget as Text).data == reply);
          await Scrollable.ensureVisible(target,
              alignment: .18, duration: const Duration(milliseconds: 300));
        case 'draftState':
          EditableText? input;
          void visit(Element element) {
            if (element.widget is Offstage &&
                (element.widget as Offstage).offstage) {
              return;
            }
            if (element.widget is EditableText &&
                element.findAncestorWidgetOfExactType<AssistantChatScreen>() !=
                    null) {
              input = element.widget as EditableText;
            }
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'text': input!.controller.text,
            'direction': input!.textDirection?.name,
            'selectionOffset': input!.controller.selection.baseOffset,
          }));
        case 'state':
          final types = <String>{};
          void visit(Element element) {
            if (element.widget is Offstage &&
                (element.widget as Offstage).offstage) {
              return;
            }
            types.add(element.widget.runtimeType.toString());
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'uid': context.read<AuthProvider>().currentUser?.id,
            'role': context.read<AuthProvider>().currentUser?.role.name,
            'googleLinked': context.read<AuthProvider>().isGoogleLinked,
            'locale': context.read<LocaleProvider>().locale.languageCode,
            'screenTypes': types
                .where(
                    (type) => type.endsWith('Screen') || type.endsWith('Shell'))
                .toList(),
          }));
      }
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    } catch (_) {
      return developer.ServiceExtensionResponse.error(
          -32000, 'Local synthetic QA action failed');
    }
  });
  app.main();
}
