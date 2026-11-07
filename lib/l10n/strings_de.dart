// Deutsche Texte. Platzhalter haben die Form {0}, {1}.
const Map<String, String> deStrings = {
  'appName': 'Intelligenter Support',
  'workbenchTitle': 'Support-Arbeitsplatz',
  'cancel': 'Abbrechen',
  'retry': 'Erneut versuchen',
  'close': 'Schließen',
  'later': 'Später',
  'logout': 'Abmelden',
  'logoutConfirm': 'Vom aktuellen Konto abmelden?',
  'logoutAction': 'Abmelden',
  'followSystem': 'Systemeinstellung folgen',
  'language': 'Sprache',
  'languageMenu': 'Sprache: {0}',

  // Anmeldung
  'loginSubtitle': 'Mobiler Support-Arbeitsplatz',
  'account': 'Konto',
  'password': 'Passwort',
  'showPassword': 'Passwort anzeigen',
  'hidePassword': 'Passwort verbergen',
  'loginButton': 'Anmelden',
  'loginEmptyError': 'Bitte Konto und Passwort eingeben',
  'loginTokenMissing': 'Der Anmeldeantwort fehlt ein Token',

  // Mandantenauswahl
  'selectTenantTitle': 'Mandant wählen',
  'searchTenantHint': 'Mandantenname oder ID suchen',
  'platformAdmin': '{0} · Plattform-Administrator',
  'tenantSelectHint':
      'Gespräche und Statistiken werden nach Mandant gefiltert. Wählen Sie den Mandanten zum Einstieg.',
  'tenantLoadFailed': 'Mandanten konnten nicht geladen werden',
  'noTenants': 'Keine Mandanten verfügbar',
  'noMatchingTenants': 'Keine passenden Mandanten',
  'noTenantsHint': 'Erstellen Sie zuerst einen Mandanten in der Admin-Konsole',
  'tryAnotherKeyword': 'Versuchen Sie ein anderes Stichwort',
  'tenantSwitchHint':
      'Nach dem Wechsel werden Gespräche und Statistiken für den neuen Mandanten neu geladen',
  'tenantFallback': 'Mandant Nr. {0}',
  'currentTenant': 'Aktueller Mandant',
  'tenantIdLabel': 'ID {0}',
  'noTenantSelected': 'Kein Mandant ausgewählt',

  // Arbeitsplatz
  'keepAliveTitle': 'Nachrichtenbenachrichtigungen aktivieren',
  'keepAliveAndroidBody':
      'Um Besuchernachrichten im Hintergrund zeitnah zu erhalten, muss der Intelligente Support eine dauerhafte Benachrichtigung anzeigen und im Hintergrund laufen dürfen.\n\nWir empfehlen außerdem, die Akku-Optimierung auszunehmen; manche Telefone erfordern zudem die Freigabe des Autostarts in den Systemeinstellungen.',
  'keepAliveIosBody':
      'Um Besuchernachrichten im Mitteilungszentrum zu sehen, erlauben Sie bitte die Benachrichtigungsberechtigung.\n\nUnter iOS erfolgen Echtzeit-Benachrichtigungen über System-Push (APNs); die App muss nicht im Hintergrund laufen.',
  'goEnable': 'Aktivieren',
  'notifOn': 'Benachrichtigungen aktiviert',
  'notifOff': 'Benachrichtigungen nicht autorisiert',
  'bgOn': 'Hintergrundausführung erlaubt',
  'bgOff': 'Hintergrundausführung nicht autorisiert',
  'listSeparator': ', ',
  'notifOffDialogBody':
      'Benachrichtigungen müssen in den Systemeinstellungen erlaubt werden, um neue Nachrichten im Mitteilungszentrum zu sehen.',
  'openSettings': 'Einstellungen öffnen',
  'soundOnToast': 'Ton für neue Nachrichten aktiviert',
  'soundOffToast': 'Ton für neue Nachrichten deaktiviert',
  'translateOnToast': 'Automatische Übersetzung aktiviert',
  'translateOffToast': 'Automatische Übersetzung deaktiviert',
  'switchTenant': 'Mandant wechseln',
  'autoTranslateOn': 'Automatische Übersetzung: Ein',
  'autoTranslateOff': 'Automatische Übersetzung: Aus',
  'soundMenuOn': 'Ton: Ein',
  'soundMenuOff': 'Ton: Aus',
  'tabConversations': 'Gespräche',
  'tabStats': 'Statistik',

  // Status
  'statusActive': 'Läuft',
  'statusHuman': 'Agent nötig',
  'statusClosed': 'Geschlossen',
  'statusUnknown': 'Unbekannt',
  'all': 'Alle',
  'allProjects': 'Alle Projekte',
  'projectFilter': 'Nach Projekt filtern',
  'projectFallback': 'Projekt Nr. {0}',

  // Gesprächsliste
  'onlineOnToast': 'Online. Neue Gespräche werden Ihnen zuerst zugewiesen',
  'onlineOffToast':
      'Offline. Es werden keine neuen Gespräche zugewiesen (bereits betreute sind nicht betroffen)',
  'switching': 'Wird gewechselt',
  'online': 'Online',
  'offline': 'Offline',
  'conversationQueue': 'Gesprächswarteschlange',
  'totalCount': '{0} gesamt',
  'resetFilters': 'Filter zurücksetzen',
  'searchConversationHint': 'Gesprächstitel / Besucher suchen',
  'clear': 'Löschen',
  'conversationLoadFailed': 'Gespräche konnten nicht geladen werden',
  'noConversations': 'Keine Gespräche',
  'noConversationsHint':
      'Ändern Sie die Filter oder warten Sie auf eine neue Besuchernachricht',
  'loadMore': 'Mehr laden ({0}/{1})',
  'allLoaded': 'Alle {0} geladen',
  'agentLabel': 'Agent {0}',
  'unassigned': 'Nicht zugewiesen',

  // Chat
  'senderAgent': 'Agent',
  'senderAi': 'KI',
  'senderSystem': 'System',
  'imageUploadFailed': 'Bild-Upload fehlgeschlagen, bitte erneut versuchen',
  'maxImages': 'Maximal {0} Bilder pro Nachricht',
  'imagesTooLarge': '{0} Bild(er) überschritten 5 MB und wurden übersprungen',
  'pickImageFailed': 'Bildauswahl fehlgeschlagen: {0}',
  'imagePlaceholder': '[Bild]',
  'imageLoadFailed': 'Bild konnte nicht geladen werden',
  'closeConversation': 'Gespräch schließen',
  'closeConversationBody':
      'Beim Schließen endet das aktuelle Gespräch für den Besucher; eine spätere Antwort öffnet es automatisch wieder.',
  'conversationClosed': 'Gespräch geschlossen',
  'conversationReopened': 'Gespräch wieder geöffnet',
  'historyForms': 'Formularverlauf ({0})',
  'noForms': 'Keine Formulardaten',
  'formData': 'Formulardaten',
  'refreshMessages': 'Nachrichten aktualisieren',
  'reopenConversation': 'Gespräch wieder öffnen',
  'newMessages': '{0} neue Nachrichten',
  'messageLoadFailed': 'Nachrichten konnten nicht geladen werden',
  'noMessages': 'Noch keine Nachrichten',
  'noMessagesHint': 'Besuchernachrichten erscheinen hier',
  'loadOlder': 'Ältere Nachrichten laden',
  'formTag': '[ Formular ] #{0}',
  'showTranslation': 'Übersetzung anzeigen',
  'showOriginal': 'Original anzeigen',
  'formSubmitNo': 'Übermittlung Nr. {0}',
  'formParseFailed': '(Formularinhalt konnte nicht verarbeitet werden)',
  'openLinkFailed': 'Link kann nicht geöffnet werden: {0}',
  'closedBarHint':
      'Gespräch geschlossen. Beim Senden einer Nachricht wird es automatisch wieder geöffnet',
  'replyHint': 'Antwort eingeben…',

  // Statistik
  'summaryUpdated': 'Zusammenfassung aktualisiert',
  'daysRange': '{0} Tage',
  'kpiConversations': 'Gespräche',
  'kpiConversationsSub': 'Neu in den letzten {0} Tagen',
  'kpiAiAnswers': 'KI-Antworten',
  'kpiAiSub': 'Durchschnittlich {0} Runden pro Gespräch',
  'kpiHuman': 'Von Menschen betreute Gespräche',
  'kpiHumanSubWithRate': '{0} der Gespräche · {1} Übergaben',
  'kpiHumanSubNoRate': 'Anteil — · {0} Übergaben',
  'kpiKb': 'Trefferquote der Wissensdatenbank',
  'kpiKbSub': '{0} Suchen, {1} Treffer',
  'kpiKbEmpty': 'In diesem Zeitraum keine Suchen',
  'chartConvTitle': 'Tägliche Gespräche und KI-Antworten',
  'chartConvTip':
      'Tage ohne Daten werden mit 0 aufgefüllt, damit die Linie zwei Tage nicht direkt verbindet',
  'legendNewConv': 'Neue Gespräche',
  'legendAiAnswer': 'KI-Antworten',
  'chartHumanTitle': 'Täglich von Menschen betreute Gespräche',
  'chartHumanTip':
      'Menschliche Betreuung zählt eindeutige Gespräche mit Agentennachrichten an diesem Tag',
  'legendHumanConv': 'Menschliche Betreuung',
  'legendTransfer': 'Übergabeanfragen',
  'legendHuman': 'Menschliche Betreuung',
  'legendTransferShort': 'Übergabe',
  'chartKbTitle': 'Tägliche Wissenssuchen und Treffer',
  'chartKbTip':
      'Die KI sucht einmal pro Antwort; Fehltreffer zählen ebenfalls als Suchen',
  'legendKbSearch': 'Suchen',
  'legendKbHit': 'Treffer',
  'noDataInRange': 'Keine Daten in diesem Zeitraum',
  'tooltipSearch': 'Suche',
  'tooltipHit': 'Treffer',
  'keywordsTitle': 'Beliebte Schlüsselwörter / Themen',
  'keywordsTip': 'Die KI fasst Besucherfragen regelmäßig zusammen',
  'keywordsEmpty':
      'In diesem Zeitraum keine für Statistiken nutzbaren Besucherfragen',
  'topKbTitle': 'Am häufigsten zitierte Wissenseinträge',
  'topKbTip': 'Sortiert nach KI-Suchtreffern',
  'topKbEmpty': 'In diesem Zeitraum keine Treffer der Wissensdatenbank',
  'summaryTitle': 'KI-Themenzusammenfassung',
  'summaryTip':
      'Besucherfragen dieses Zeitraums in wenigen Kernpunkten zusammenfassen',
  'genSummary': 'KI-Zusammenfassung erstellen',
  'summaryMeta': 'Modell {0} · erstellt am {1}',
  'summaryLoading': 'Zusammenfassung läuft, bitte warten (etwa zehn Sekunden)…',
  'summaryEmpty':
      'Noch keine Zusammenfassung erstellt. Tippen Sie oben rechts, damit die KI die Besucherfragen dieses Zeitraums in Kernpunkten zusammenfasst.',
  'summaryNote':
      'Die Zusammenfassung ruft das Modell live auf, dauert etwa zehn Sekunden und verbraucht Token.',

  // Fehler
  'sessionExpired': 'Sitzung abgelaufen, bitte erneut anmelden',
  'requestFailed': 'Anfrage fehlgeschlagen',
  'networkTimeout':
      'Netzwerk-Zeitüberschreitung, bitte später erneut versuchen',
  'cannotConnect': 'Server nicht erreichbar, bitte Netzwerk prüfen',
  'httpError': 'Server hat einen Fehler zurückgegeben (HTTP {0})',
  'networkError': 'Netzwerkfehler',

  // Benachrichtigungen
  'notifChannelName': 'Besuchernachrichten',
  'notifChannelSilentName': 'Besuchernachrichten (lautlos)',
  'notifChannelDesc':
      'Benachrichtigen, wenn eine neue Besuchernachricht eintrifft',
  'fgChannelName': 'Intelligenter Support online',
  'fgChannelDesc': 'Verbindung halten, um Besuchernachrichten zu erhalten',
  'fgNotificationText': 'Empfange Besuchernachrichten im Hintergrund',
  'visitor': 'Besucher',
  'unreadMessages': '{0} ungelesene Nachrichten',
  'newMessageTitle': 'Neue Nachricht von {0}',

  // Sonstiges
  'yesterday': 'Gestern {0}',

  // Login-Einstiege
  'loginIntroEntry': 'Plattform-Übersicht',
  'loginRegisterEntry': 'Firmenregistrierung',
  'introBody':
      'Eine komplette Kunden-Support-Plattform – vom Web-Backend bis zur mobilen App\n\n· Multichannel-Eingang: Kundenanfragen aus Website, App und Mini-Programmen laufen in einem Arbeitsbereich zusammen\n· Firmen-Backend: Nach der Registrierung konfigurieren Sie im Web-Backend Empfangsregeln, Agententeams und Wissensdatenbank\n· Mobiler Dienst: Gespräche werden in Echtzeit aufs Handy gepusht – auch unterwegs können Sie übernehmen, zuweisen und antworten\n· Dashboard: Gesprächsvolumen, Erstantwortzeit und Zufriedenheitstrends auf einen Blick\n· Weltweit verfügbar: 11 Sprachen folgen automatisch dem System, für internationale Teams\n\nSo starten Sie: Öffnen Sie zuerst support.breathmeters.net im Browser auf einem PC, registrieren Sie Ihr Unternehmen und konfigurieren Sie das Backend. Danach melden Sie sich mit demselben Firmenkonto in dieser App an, um Kunden zu betreuen.',
  'registerBody':
      'Die Firmenregistrierung muss im Browser auf einem PC erfolgen.\nKopieren Sie den Link und öffnen Sie ihn im PC-Browser.\n\nDie mobile App dient nur zur Anmeldung mit einem registrierten Firmenkonto.',
  'copyLink': 'Link kopieren',
  'linkCopied': 'Link kopiert',
};
