// Textes en français. Les espaces réservés utilisent {0}, {1}.
const Map<String, String> frStrings = {
  'appName': 'xChat',
  'workbenchTitle': 'Console de support',
  'cancel': 'Annuler',
  'retry': 'Réessayer',
  'close': 'Fermer',
  'later': 'Plus tard',
  'logout': 'Se déconnecter',
  'logoutConfirm': 'Se déconnecter du compte actuel ?',
  'logoutAction': 'Se déconnecter',
  'followSystem': 'Suivre le système',
  'language': 'Langue',
  'languageMenu': 'Langue : {0}',

  // Connexion
  'loginSubtitle': 'Console de support mobile',
  'account': 'Compte',
  'password': 'Mot de passe',
  'showPassword': 'Afficher le mot de passe',
  'hidePassword': 'Masquer le mot de passe',
  'loginButton': 'Se connecter',
  'loginEmptyError': 'Saisissez le compte et le mot de passe',
  'loginTokenMissing': 'La réponse de connexion ne contient pas de jeton',

  // Sélection du locataire
  'selectTenantTitle': 'Choisir un locataire',
  'searchTenantHint': 'Rechercher le nom ou l\'ID du locataire',
  'platformAdmin': '{0} · Administrateur de plateforme',
  'tenantSelectHint':
      'Les conversations et les statistiques sont filtrées par locataire. Choisissez celui à ouvrir.',
  'tenantLoadFailed': 'Échec du chargement des locataires',
  'noTenants': 'Aucun locataire disponible',
  'noMatchingTenants': 'Aucun locataire correspondant',
  'noTenantsHint':
      'Créez d\'abord un locataire dans la console d\'administration',
  'tryAnotherKeyword': 'Essayez un autre mot-clé',
  'tenantSwitchHint':
      'Après changement de locataire, les conversations et les statistiques sont rechargées pour le nouveau locataire',
  'tenantFallback': 'Locataire n° {0}',
  'currentTenant': 'Locataire actuel',
  'tenantIdLabel': 'ID {0}',
  'noTenantSelected': 'Aucun locataire sélectionné',

  // Console
  'keepAliveTitle': 'Activer les alertes de messages',
  'keepAliveAndroidBody':
      'Pour recevoir rapidement les messages des visiteurs en arrière-plan, Support intelligent doit afficher une notification permanente et être autorisé à s\'exécuter en arrière-plan.\n\nNous recommandons aussi d\'autoriser l\'exemption d\'optimisation de la batterie ; certains téléphones exigent également l\'autorisation du démarrage automatique dans les paramètres système.',
  'keepAliveIosBody':
      'Pour voir les messages des visiteurs dans le centre de notifications, autorisez les notifications.\n\nSur iOS, les alertes en temps réel sont gérées par le push système (APNs) ; l\'application n\'a pas besoin de rester en arrière-plan.',
  'goEnable': 'Activer',
  'supportEntry': 'Contacter le support',
  'supportTitle': 'Support en ligne',
  'supportLoading': 'Connexion au support…',
  'supportUnavailable': 'Le support est temporairement indisponible. Veuillez réessayer plus tard.',
  'notifOn': 'Notifications activées',
  'notifOff': 'Notifications non autorisées',
  'bgOn': 'Exécution en arrière-plan autorisée',
  'bgOff': 'Exécution en arrière-plan non autorisée',
  'listSeparator': ', ',
  'notifOffDialogBody':
      'Les notifications doivent être autorisées dans les paramètres système pour voir les nouveaux messages dans le centre de notifications.',
  'openSettings': 'Ouvrir les paramètres',
  'soundOnToast': 'Son des nouveaux messages activé',
  'soundOffToast': 'Son des nouveaux messages désactivé',
  'translateOnToast': 'Traduction automatique activée',
  'translateOffToast': 'Traduction automatique désactivée',
  'switchTenant': 'Changer de locataire',
  'autoTranslateOn': 'Traduction automatique : activée',
  'autoTranslateOff': 'Traduction automatique : désactivée',
  'soundMenuOn': 'Son : activé',
  'soundMenuOff': 'Son : désactivé',
  'tabConversations': 'Conversations',
  'tabStats': 'Statistiques',

  // Statut
  'statusActive': 'En cours',
  'statusHuman': 'Agent requis',
  'statusClosed': 'Fermée',
  'statusUnknown': 'Inconnu',
  'all': 'Toutes',
  'allProjects': 'Tous les projets',
  'projectFilter': 'Filtrer par projet',
  'projectFallback': 'Projet n° {0}',

  // Liste des conversations
  'onlineOnToast':
      'En ligne. Les nouvelles conversations vous seront attribuées en priorité',
  'onlineOffToast':
      'Hors ligne. Aucune nouvelle conversation ne sera attribuée (celles déjà prises en charge ne sont pas affectées)',
  'switching': 'Changement en cours',
  'online': 'En ligne',
  'offline': 'Hors ligne',
  'conversationQueue': 'File des conversations',
  'totalCount': '{0} au total',
  'resetFilters': 'Réinitialiser les filtres',
  'searchConversationHint':
      'Rechercher le titre de la conversation / le visiteur',
  'clear': 'Effacer',
  'conversationLoadFailed': 'Échec du chargement des conversations',
  'noConversations': 'Aucune conversation',
  'noConversationsHint':
      'Modifiez les filtres ou attendez un nouveau message d\'un visiteur',
  'loadMore': 'Charger plus ({0}/{1})',
  'allLoaded': 'Les {0} conversations sont chargées',
  'agentLabel': 'Agent {0}',
  'unassigned': 'Non attribuée',
  'assign': 'Attribuer un agent',
  'reassign': 'Transférer à un autre agent',
  'assignTip':
      'Seuls les membres activés, participant à l\'attribution et autorisés pour ce projet sont listés (les admins de tenant ne sont pas limités par projet). Les membres hors ligne ou hors plage peuvent être attribués, mais le visiteur attendra leur retour en ligne.',
  'assignEmpty':
      'Aucun membre attribuable : dans Membres, autorisez ce projet et activez la participation à l\'attribution',
  'assignCurrent': 'Actuel',
  'assignOffDuty': 'Hors plage',
  'agentLoad': '{0} en cours',
  'assignDone': 'Attribué à {0}',
  'confirm': 'Confirmer',
  'anonymous': 'Utilisateur anonyme',

  // Chat
  'senderAgent': 'Agent',
  'senderAi': 'IA',
  'senderSystem': 'Système',
  'imageUploadFailed': 'Échec de l\'envoi de l\'image, réessayez',
  'maxImages': 'Jusqu\'à {0} images par message',
  'imagesTooLarge': '{0} image(s) dépassaient 5 Mo et ont été ignorées',
  'pickImageFailed': 'Échec de la sélection de l\'image : {0}',
  'imagePlaceholder': '[Image]',
  'imageLoadFailed': 'Échec du chargement de l\'image',
  'closeConversation': 'Fermer la conversation',
  'closeConversationBody':
      'La fermeture met fin à la conversation actuelle du visiteur ; une réponse ultérieure la rouvrira automatiquement.',
  'conversationClosed': 'Conversation fermée',
  'conversationReopened': 'Conversation rouverte',
  'pauseAi': 'Suspendre les réponses IA',
  'resumeAi': 'Reprendre les réponses IA',
  'aiPaused': 'IA suspendue',
  'aiResumed': 'Réponses IA reprises',
  'historyForms': 'Historique des formulaires ({0})',
  'noForms': 'Aucune donnée de formulaire',
  'formData': 'Données du formulaire',
  'refreshMessages': 'Actualiser les messages',
  'reopenConversation': 'Rouvrir la conversation',
  'newMessages': '{0} nouveaux messages',
  'messageLoadFailed': 'Échec du chargement des messages',
  'noMessages': 'Aucun message pour l\'instant',
  'noMessagesHint': 'Les messages des visiteurs apparaîtront ici',
  'loadOlder': 'Charger les messages précédents',
  'formTag': '[ Formulaire ] #{0}',
  'showTranslation': 'Voir la traduction',
  'showOriginal': 'Voir l\'original',
  'formSubmitNo': 'Envoi n° {0}',
  'formParseFailed': '(Impossible d\'analyser le contenu du formulaire)',
  'openLinkFailed': 'Impossible d\'ouvrir le lien : {0}',
  'closedBarHint':
      'Conversation fermée. L\'envoi d\'un message la rouvrira automatiquement',
  'replyHint': 'Saisissez une réponse…',
  'attachImage': 'Image',
  'previewTranslation': 'Aperçu de la traduction',
  'inviteReview': 'Évaluer',
  'reviewInviteIntro':
      'Si cette application vous est utile, notez-la avec 5 étoiles sur le store :',
  'reviewInvitePlay': 'Google Play',
  'reviewInviteAppStore': 'App Store',
  'reviewInviteGo': 'Évaluer l’application sur le store',
  'reviewInviteSendTitle': 'Envoyer l’invitation d’évaluation ?',
  'reviewInviteSendBtn': 'Envoyer',
  'reviewLinkNotConfigured': 'Le lien {0} n’est pas configuré. Demandez à un administrateur d’ouvrir Gestion des projets dans la console web, de modifier ce projet (type APP) et de renseigner le lien du store, puis réessayez.',
  'visitorWillSee': 'Ce que recevra le visiteur (modifiable)',
  'retranslate': 'Retraduire',
  'translationSameLang': 'Déjà dans la langue du visiteur',
  'translationStale': 'Texte source modifié, traduction à mettre à jour',
  'userInfo': 'Informations utilisateur',
  'userName': 'Nom',
  'userAccount': 'Compte',
  'userPhone': 'Téléphone',
  'userEmail': 'E-mail',
  'userExternalId': 'ID utilisateur externe',
  'userProject': 'Projet',
  'userRegTime': "Date d'inscription",
  'userRemark': 'Remarque',
  'userInfoLoadFailed':
      'Erreur lors du chargement des informations utilisateur',

  // Statistiques
  'summaryUpdated': 'Résumé mis à jour',
  'daysRange': '{0} jours',
  'kpiConversations': 'Conversations',
  'kpiConversationsSub': 'Nouvelles sur les {0} derniers jours',
  'kpiAiAnswers': 'Réponses de l\'IA',
  'kpiAiSub': 'Moyenne de {0} échanges par conversation',
  'kpiHuman': 'Conversations traitées par des agents',
  'kpiHumanSubWithRate': '{0} des conversations · {1} transferts',
  'kpiHumanSubNoRate': 'Part — · {0} transferts',
  'kpiKb': 'Taux de pertinence de la base de connaissances',
  'kpiKbSub': '{0} recherches, {1} correspondances',
  'kpiKbEmpty': 'Aucune recherche sur cette période',
  'chartConvTitle': 'Conversations et réponses de l\'IA par jour',
  'chartConvTip':
      'Les jours sans données sont complétés par 0 pour que la courbe ne relie pas deux jours directement',
  'legendNewConv': 'Nouvelles conversations',
  'legendAiAnswer': 'Réponses de l\'IA',
  'chartHumanTitle': 'Conversations traitées par des agents par jour',
  'chartHumanTip':
      'Le traitement humain compte les conversations uniques avec des messages d\'agent ce jour-là',
  'legendHumanConv': 'Traitement humain',
  'legendTransfer': 'Demandes de transfert',
  'legendHuman': 'Traitement humain',
  'legendTransferShort': 'Transfert',
  'chartKbTitle':
      'Recherches et correspondances de la base de connaissances par jour',
  'chartKbTip':
      'L\'IA effectue une recherche par réponse ; les échecs comptent aussi comme recherches',
  'legendKbSearch': 'Recherches',
  'legendKbHit': 'Correspondances',
  'noDataInRange': 'Aucune donnée sur cette période',
  'tooltipSearch': 'Recherche',
  'tooltipHit': 'Correspondance',
  'keywordsTitle': 'Mots-clés / sujets populaires',
  'keywordsTip':
      'L\'IA résume périodiquement les sujets des questions des visiteurs',
  'keywordsEmpty':
      'Aucune question de visiteur exploitable pour les statistiques sur cette période',
  'topKbTitle': 'Entrées de connaissances les plus citées',
  'topKbTip': 'Triées par correspondances de recherche de l\'IA',
  'topKbEmpty':
      'Aucune correspondance de la base de connaissances sur cette période',
  'summaryTitle': 'Résumé des sujets par l\'IA',
  'summaryTip':
      'Résumer les questions des visiteurs de cette période en quelques points clés',
  'genSummary': 'Générer un résumé IA',
  'summaryMeta': 'Modèle {0} · généré le {1}',
  'summaryLoading':
      'Résumé en cours, veuillez patienter (une dizaine de secondes)…',
  'summaryEmpty':
      'Aucun résumé généré pour l\'instant. Appuyez sur le bouton en haut à droite pour que l\'IA résume les questions des visiteurs de cette période en points clés.',
  'summaryNote':
      'Le résumé appelle le modèle en direct, prend une dizaine de secondes et consomme des tokens.',

  // Erreurs
  'sessionExpired': 'Session expirée, reconnectez-vous',
  'requestFailed': 'Échec de la requête',
  'networkTimeout': 'Délai réseau dépassé, réessayez plus tard',
  'cannotConnect':
      'Impossible de se connecter au serveur, vérifiez votre réseau',
  'httpError': 'Le serveur a renvoyé une erreur (HTTP {0})',
  'networkError': 'Erreur réseau',

  // Notifications
  'notifChannelName': 'Messages des visiteurs',
  'notifChannelSilentName': 'Messages des visiteurs (silencieux)',
  'notifChannelDesc':
      'Alerter à l\'arrivée d\'un nouveau message d\'un visiteur',
  'fgChannelName': 'Support intelligent en ligne',
  'fgChannelDesc':
      'Maintenir la connexion pour recevoir les messages des visiteurs',
  'fgNotificationText': 'Réception des messages des visiteurs en arrière-plan',
  'visitor': 'Visiteur',
  'unreadMessages': '{0} messages non lus',
  'newMessageTitle': 'Nouveau message de {0}',

  // Divers
  'yesterday': 'Hier {0}',

  // Entrées de connexion
  'loginIntroEntry': 'Présentation de la plateforme',
  'loginRegisterEntry': 'Inscription entreprise',
  'introBody':
      '''Une plateforme de support client complète, du back-office web à l'app mobile

· Réception multicanal : les demandes des clients venant du site web et de l'app sont réunies dans un seul espace de travail
· Back-office entreprise : après inscription, configurez les règles de réception, les équipes d'agents et la base de connaissances dans le back-office web
· Service mobile : les conversations sont poussées en temps réel sur le téléphone ; même en déplacement, vous pouvez prendre le relais, attribuer et répondre
· Tableau de bord : volume de conversations, temps de première réponse et tendances de satisfaction en un coup d'œil
· Disponible partout : 11 langues suivent automatiquement le système, pour les équipes internationales

Comment démarrer : ouvrez d'abord https://reflexassist.com dans un navigateur sur PC pour enregistrer votre entreprise et configurer le back-office, puis connectez-vous à cette app avec le même compte entreprise pour assurer le service''',
  'registerBody':
      'L\'inscription d\'une entreprise doit être effectuée dans le navigateur d\'un PC.\nCopiez le lien ci-dessous et ouvrez-le sur un PC.\n\nL\'app mobile sert uniquement à se connecter avec un compte entreprise déjà enregistré.',
  'copyLink': 'Copier le lien',
  'linkCopied': 'Lien copié',
  'copied': 'Copié',

  // Contacts
  'tabContacts': 'Contacts',
  'contactsSearchHint': 'Rechercher nom / compte / téléphone / e-mail',
  'contactsSyncTip':
      'Les contacts sont synchronisés automatiquement par l’API ouverte ; seules les infos d’affichage sont gérées ici',
  'contactsEmpty': 'Aucun contact',
  'contactsLoadFailed': 'Échec du chargement des contacts',
  'contactEnabled': 'Activé',
  'contactDisabled': 'Désactivé',
  'editContact': 'Modifier le contact',
  'deleteContact': 'Supprimer',
  'deleteContactConfirm':
      'Supprimer ce contact ? Les conversations existantes ne sont pas affectées.',
  'save': 'Enregistrer',
  'contactSaved': 'Enregistré',
  'contactDeleted': 'Supprimé',
  'openConversation': 'Ouvrir la conversation',
  'tags': 'Étiquettes',
  'setTags': 'Définir les étiquettes',
  'manageTags': 'Gérer les étiquettes',
  'noTags': 'Aucune étiquette',
  'noTagsHint':
      'Demandez à un administrateur de créer des étiquettes dans la console web',
  'noTagsHintManage': 'Aucune étiquette. Appuyez sur + pour en créer',
  'searchTags': 'Rechercher des étiquettes',
  'noTagMatch': 'Aucune étiquette correspondante',
  'tagFilter': 'Étiquettes',
  'filterTags': 'Filtrer par étiquettes',
  'tagFilterCount': 'Étiquettes · {0}',
  'newTag': 'Nouvelle étiquette',
  'editTag': "Modifier l'étiquette",
  'tagName': "Nom de l'étiquette",
  'deleteTag': "Supprimer l'étiquette",
  'deleteTagConfirm':
      "Supprimer cette étiquette ? Elle sera retirée de tous les visiteurs.",
  'tagsUpdated': 'Étiquettes mises à jour',
  'done': 'Terminé',

  // Plateforme du visiteur : détectée côté serveur d'après le User-Agent du H5, stockée dans chat_user.platform
  'platformLabel': 'Plateforme',
  'platAndroid': 'Android',
  'platIos': 'iOS',
  'platHarmony': 'HarmonyOS',
  'platWindows': 'Windows',
  'platMacos': 'macOS',
  'platLinux': 'Linux',
  'platOther': 'Autres',
  'platUnknown': 'Inconnue',
};
