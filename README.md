# F76 Roadmap Extractor

[English version](README.en.md)

Outil macOS local pour extraire les événements d'une saison Fallout 76 à partir d'une image de roadmap officielle, puis les exporter en JSON.

Le but principal du projet est de transformer une image communautaire officielle en données structurées utilisables par l'écosystème [f76-tools](https://github.com/Grandpere/f76-tools), notamment pour afficher et exploiter le calendrier des événements dans une interface web.

Le projet fonctionne entièrement en local :

- sans abonnement
- sans API externe
- sans dépendance OCR payante
- en s'appuyant sur `Vision`, l'OCR natif Apple

## Aperçu

![Capture de l'application](docs/screenshots/app-main.png)
![Capture de l'onglet résultats](docs/screenshots/app-main-result-tab.png)
![Capture de l'onglet JSON](docs/screenshots/app-main-result-json.png)

## Fonctionnalités

- extraction OCR depuis des images de roadmaps Fallout 76 officielles
- parsing spécialisé des dates et événements de saison
- export JSON stable pour intégration web
- support actuel des locales `FR`, `EN` et `DE`
- interface graphique macOS pour éviter la ligne de commande
- sortie debug pour diagnostiquer les cas OCR difficiles
- packaging en vraie app `.app` et en `.dmg`

## Cas d'usage

Workflow visé :

1. récupérer la roadmap officielle d'une nouvelle saison
2. lancer l'extraction sur l'image FR, EN ou DE
3. produire un `calendar-web.json`
4. réutiliser ce JSON dans [f76-tools](https://github.com/Grandpere/f76-tools)

Le projet a été entraîné et durci à partir d'anciennes images de saisons afin de mieux gérer :

- les titres bruités
- les dates tronquées
- les visuels chargés
- les OCR imparfaits

Des exemples d'images compatibles sont disponibles dans :

- [f76-tools / data / roadmap_calendar_examples](https://github.com/Grandpere/f76-tools/tree/main/data/roadmap_calendar_examples)

## Prérequis

- macOS 13 ou plus récent
- outils développeur Apple installés

Vérification rapide :

```bash
xcode-select -p
```

Si nécessaire :

```bash
xcode-select --install
```

## Installation

Cloner le dépôt :

```bash
git clone <url-du-repo>
cd ocr
```

Build de l'app macOS :

```bash
xcrun swift build --scratch-path .build-scratch --product F76RoadmapExtractor
```

Build des smoke tests :

```bash
xcrun swift build --scratch-path .build-scratch --product ocr-smoketests
```

## Utilisation en ligne de commande

Extraction simple :

```bash
xcrun swift run --scratch-path .build-scratch ocr \
  --image /chemin/vers/calendrier.jpg \
  --locale fr-FR \
  --base-year 2026
```

Export direct du JSON pour l'outil web :

```bash
xcrun swift run --scratch-path .build-scratch ocr \
  --image /chemin/vers/calendrier.jpg \
  --locale fr-FR \
  --web-json ./calendar-web.json
```

Export debug complet :

```bash
xcrun swift run --scratch-path .build-scratch ocr \
  --image /chemin/vers/calendrier.jpg \
  --locale fr-FR \
  --base-year 2026 \
  --debug-dir ./debug-calendar
```

Le dossier debug contient :

- `calendar-web.json` : sortie JSON prête pour l'intégration
- `result.json` : résultat interne détaillé
- `debug.json` : traces OCR et fusion des lignes
- `raw-lines.txt` : texte OCR fusionné

## Format JSON cible

Le format principal consommé par l'outil web est :

```json
{
  "season": 24,
  "name": "Forêt Sauvage",
  "events": [
    {
      "date_start": "2026-03-03",
      "date_end": "2026-03-03",
      "title": "Mise à jour Forêt sauvage"
    }
  ]
}
```

Règles actuelles :

- dates au format ISO 8601
- événements triés par `date_start`
- `date_end` obligatoire
- titres conservés dans la langue de l'image
- `season` et `name` déduits depuis l'image quand possible

## Interface graphique macOS

Lancer l'app :

```bash
xcrun swift run --scratch-path .build-scratch F76RoadmapExtractor
```

L'interface permet :

- de choisir ou glisser-déposer une image
- de sélectionner `FR`, `EN` ou `DE`
- de saisir ou préremplir l'année de base
- de voir les événements extraits
- de prévisualiser le JSON web
- de copier le JSON dans le presse-papiers
- d'exporter `calendar-web.json`, `result.json` ou un bundle debug
- de rouvrir rapidement les dernières images utilisées

## Générer une vraie app macOS

Créer le bundle `.app` :

```bash
./scripts/build-app.sh
```

Sortie :

```bash
./dist/F76 Roadmap Extractor.app
```

Par défaut, l'app est signée localement en ad-hoc.

Pour utiliser une vraie identité `codesign` :

```bash
SIGN_IDENTITY="Developer ID Application: Ton Nom (TEAMID)" ./scripts/build-app.sh
```

## Générer un DMG

Créer le `.dmg` :

```bash
./scripts/build-dmg.sh
```

Sortie :

```bash
./dist/F76 Roadmap Extractor.dmg
```

Le script essaie d'abord de générer un DMG stylé. Si macOS bloque la phase cosmétique Finder, il retombe automatiquement sur un DMG simple mais valide.

## Vérification

Lancer les smoke tests :

```bash
xcrun swift run --scratch-path .build-scratch ocr-smoketests
```

## État actuel

- `FR` : bon niveau de fiabilité
- `EN` : bon niveau de fiabilité
- `DE` : bon niveau de fiabilité sur les vraies images allemandes disponibles

Le moteur a été optimisé pour une famille de visuels précise : les roadmaps officielles Fallout 76. Il ne s'agit pas d'un OCR générique pour n'importe quel calendrier.

## Limitations connues

- certaines images très bruitées peuvent produire des titres partiellement OCRisés
- l'inférence d'année peut nécessiter `--base-year` si le copyright est mal lu
- certaines images marquées `DE` dans les archives historiques ne sont pas réellement en allemand
- la notarization Apple n'est pas incluse dans ce projet

## Stack technique

- `Swift`
- `Vision`
- `SwiftUI`
- packaging macOS via scripts shell

## Projet lié

Le JSON exporté par cet outil est destiné à être réutilisé dans :

- [f76-tools](https://github.com/Grandpere/f76-tools)
