import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/components/custom_app_bar.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/import_export.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AddAppPage extends StatefulWidget {
  const AddAppPage({super.key});

  @override
  State<AddAppPage> createState() => _AddAppPageState();
}

class _AddAppPageState extends State<AddAppPage> {
  bool gettingAppInfo = false;

  String userInput = '';
  String searchQuery = '';
  AppSource? pickedSource;
  List<String> sourceSpecificAdditionalData = [];
  bool sourceSpecificDataIsValid = true;
  List<String> otherAdditionalData = [];
  bool otherAdditionalDataIsValid = true;

  @override
  Widget build(BuildContext context) {
    SourceProvider sourceProvider = SourceProvider();
    AppsProvider appsProvider = context.read<AppsProvider>();

    changeUserInput(String input, bool valid, bool isBuilding) {
      userInput = input;
      fn() {
        var source = valid ? sourceProvider.getSource(userInput) : null;
        if (pickedSource != source) {
          pickedSource = source;
          sourceSpecificAdditionalData =
              source != null ? source.additionalSourceAppSpecificDefaults : [];
          sourceSpecificDataIsValid = source != null
              ? sourceProvider.ifSourceAppsRequireAdditionalData(source)
              : true;
        }
      }

      if (isBuilding) {
        fn();
      } else {
        setState(() {
          fn();
        });
      }
    }

    addApp({bool resetUserInputAfter = false}) async {
      setState(() {
        gettingAppInfo = true;
      });
      var settingsProvider = context.read<SettingsProvider>();
      () async {
        var userPickedTrackOnly = findGeneratedFormValueByKey(
                pickedSource!.additionalAppSpecificSourceAgnosticFormItems,
                otherAdditionalData,
                'trackOnlyFormItemKey') ==
            'true';
        var cont = true;
        if ((userPickedTrackOnly || pickedSource!.enforceTrackOnly) &&
            await showDialog(
                    context: context,
                    builder: (BuildContext ctx) {
                      return GeneratedFormModal(
                        title:
                            '${pickedSource!.enforceTrackOnly ? 'Source' : 'App'} is Track-Only',
                        items: const [],
                        defaultValues: const [],
                        message:
                            '${pickedSource!.enforceTrackOnly ? 'Apps from this source are \'Track-Only\'.' : 'You have selected the \'Track-Only\' option.'}\n\nThe App will be tracked for updates, but Obtainium will not be able to download or install it.',
                      );
                    }) ==
                null) {
          cont = false;
        }
        if (cont) {
          HapticFeedback.selectionClick();
          var trackOnly = pickedSource!.enforceTrackOnly || userPickedTrackOnly;
          App app = await sourceProvider.getApp(
              pickedSource!, userInput, sourceSpecificAdditionalData,
              trackOnly: trackOnly);
          if (!trackOnly) {
            await settingsProvider.getInstallPermission();
          }
          // Only download the APK here if you need to for the package ID
          if (sourceProvider.isTempId(app.id) && !app.trackOnly) {
            // ignore: use_build_context_synchronously
            var apkUrl = await appsProvider.confirmApkUrl(app, context);
            if (apkUrl == null) {
              throw ObtainiumError('Cancelled');
            }
            app.preferredApkIndex = app.apkUrls.indexOf(apkUrl);
            var downloadedApk = await appsProvider.downloadApp(app);
            app.id = downloadedApk.appId;
          }
          if (appsProvider.apps.containsKey(app.id)) {
            throw ObtainiumError('App already added');
          }
          if (app.trackOnly) {
            app.installedVersion = app.latestVersion;
          }
          await appsProvider.saveApps([app]);

          return app;
        }
      }()
          .then((app) {
        if (app != null) {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => AppPage(appId: app.id)));
        }
      }).catchError((e) {
        showError(e, context);
      }).whenComplete(() {
        setState(() {
          gettingAppInfo = false;
          if (resetUserInputAfter) {
            changeUserInput('', false, true);
          }
        });
      });
    }

    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: CustomScrollView(slivers: <Widget>[
          const CustomAppBar(title: 'Add App'),
          SliverFillRemaining(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: GeneratedForm(
                                  items: [
                                    [
                                      GeneratedFormItem(
                                          label: 'App Source Url',
                                          additionalValidators: [
                                            (value) {
                                              try {
                                                sourceProvider
                                                    .getSource(value ?? '')
                                                    .standardizeURL(
                                                        preStandardizeUrl(
                                                            value ?? ''));
                                              } catch (e) {
                                                return e is String
                                                    ? e
                                                    : e is ObtainiumError
                                                        ? e.toString()
                                                        : 'Error';
                                              }
                                              return null;
                                            }
                                          ])
                                    ]
                                  ],
                                  onValueChanges: (values, valid, isBuilding) {
                                    changeUserInput(
                                        values[0], valid, isBuilding);
                                  },
                                  defaultValues: const [])),
                          const SizedBox(
                            width: 16,
                          ),
                          gettingAppInfo
                              ? const CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: gettingAppInfo ||
                                          pickedSource == null ||
                                          (pickedSource!
                                                  .additionalSourceAppSpecificFormItems
                                                  .isNotEmpty &&
                                              !sourceSpecificDataIsValid) ||
                                          (pickedSource!
                                                  .additionalAppSpecificSourceAgnosticDefaults
                                                  .isNotEmpty &&
                                              !otherAdditionalDataIsValid)
                                      ? null
                                      : addApp,
                                  child: const Text('Add'))
                        ],
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      if (sourceProvider.sources
                              .where((e) => e.canSearch)
                              .isNotEmpty &&
                          pickedSource == null)
                        Row(
                          children: [
                            Expanded(
                              child: GeneratedForm(
                                  items: [
                                    [
                                      GeneratedFormItem(
                                          label: 'Search (Some Sources Only)',
                                          required: false),
                                    ]
                                  ],
                                  onValueChanges: (values, valid, isBuilding) {
                                    if (values.isNotEmpty && valid) {
                                      setState(() {
                                        searchQuery = values[0].trim();
                                      });
                                    }
                                  },
                                  defaultValues: const ['']),
                            ),
                            const SizedBox(
                              width: 16,
                            ),
                            ElevatedButton(
                                onPressed: searchQuery.isEmpty || gettingAppInfo
                                    ? null
                                    : () {
                                        Future.wait(sourceProvider.sources
                                                .where((e) => e.canSearch)
                                                .map((e) =>
                                                    e.search(searchQuery)))
                                            .then((results) async {
                                          var res = // TODO: Interleave results
                                              results.reduce((value, element) {
                                            value.addAll(element);
                                            return value;
                                          });
                                          // Map<String, String> res = {};
                                          // var si = 0;
                                          // var done = false;
                                          // for (var r in results) {
                                          //   if (r.length > si) {
                                          //     res.addEntries(r.entries.toList()[si]);
                                          //   }
                                          // }
                                          // for (var rs in results) {
                                          //   for (var r in rs.entries) {}
                                          // }
                                          List<String>? selectedUrls = res
                                                  .isEmpty
                                              ? []
                                              : await showDialog<List<String>?>(
                                                  context: context,
                                                  builder: (BuildContext ctx) {
                                                    return UrlSelectionModal(
                                                      urlsWithDescriptions: res,
                                                      selectedByDefault: false,
                                                      onlyOneSelectionAllowed:
                                                          true,
                                                    );
                                                  });
                                          if (selectedUrls != null &&
                                              selectedUrls.isNotEmpty) {
                                            changeUserInput(
                                                selectedUrls[0], true, true);
                                            addApp(resetUserInputAfter: true);
                                          }
                                        }).catchError((e) {
                                          showError(e, context);
                                        });
                                      },
                                child: const Text('Search'))
                          ],
                        ),
                      if (pickedSource != null &&
                          (pickedSource!.additionalSourceAppSpecificDefaults
                                  .isNotEmpty ||
                              pickedSource!
                                  .additionalAppSpecificSourceAgnosticFormItems
                                  .where((e) => pickedSource!.enforceTrackOnly
                                      ? e.key != 'trackOnlyFormItemKey'
                                      : true)
                                  .map((e) => [e])
                                  .isNotEmpty))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Divider(
                              height: 64,
                            ),
                            Text(
                                'Additional Options for ${pickedSource?.runtimeType}',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                            const SizedBox(
                              height: 16,
                            ),
                            if (pickedSource!
                                .additionalSourceAppSpecificFormItems
                                .isNotEmpty)
                              GeneratedForm(
                                  items: pickedSource!
                                      .additionalSourceAppSpecificFormItems,
                                  onValueChanges: (values, valid, isBuilding) {
                                    if (isBuilding) {
                                      sourceSpecificAdditionalData = values;
                                      sourceSpecificDataIsValid = valid;
                                    } else {
                                      setState(() {
                                        sourceSpecificAdditionalData = values;
                                        sourceSpecificDataIsValid = valid;
                                      });
                                    }
                                  },
                                  defaultValues: pickedSource!
                                      .additionalSourceAppSpecificDefaults),
                            GeneratedForm(
                                items: pickedSource!
                                    .additionalAppSpecificSourceAgnosticFormItems
                                    .where((e) => pickedSource!.enforceTrackOnly
                                        ? e.key != 'trackOnlyFormItemKey'
                                        : true)
                                    .map((e) => [e])
                                    .toList(),
                                onValueChanges: (values, valid, isBuilding) {
                                  if (isBuilding) {
                                    otherAdditionalData = values;
                                    otherAdditionalDataIsValid = valid;
                                  } else {
                                    setState(() {
                                      otherAdditionalData = values;
                                      otherAdditionalDataIsValid = valid;
                                    });
                                  }
                                },
                                defaultValues: pickedSource!
                                    .additionalAppSpecificSourceAgnosticDefaults),
                            if (pickedSource!
                                .additionalAppSpecificSourceAgnosticDefaults
                                .isNotEmpty)
                              const SizedBox(
                                height: 8,
                              ),
                          ],
                        )
                      else
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                              const Text(
                                'Supported Sources:',
                              ),
                              const SizedBox(
                                height: 8,
                              ),
                              ...sourceProvider.sources
                                  .map((e) => GestureDetector(
                                      onTap: () {
                                        launchUrlString('https://${e.host}',
                                            mode:
                                                LaunchMode.externalApplication);
                                      },
                                      child: Text(
                                        '${e.runtimeType.toString()}${e.enforceTrackOnly ? ' (Track-Only)' : ''}${e.canSearch ? ' (Searchable)' : ''}',
                                        style: const TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            fontStyle: FontStyle.italic),
                                      )))
                                  .toList()
                            ])),
                      const SizedBox(
                        height: 8,
                      ),
                    ])),
          )
        ]));
  }
}
