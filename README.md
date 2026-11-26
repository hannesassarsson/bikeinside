# Bikeinside

Ett virtuellt cykelspel för Mac. Du cyklar på din smarta trainer genom svenska landskap med skog, sjöar och fjäll. Trainern känner av backarna, och du kan köra strukturerade pass i ERG-läge eller cykla i klunga med datorstyrda medcyklister. Allt kan exporteras till Strava och Garmin.

## Kom igång

1. Öppna `Bikeinside.xcodeproj` i Xcode 16 eller senare.
2. Välj schemat **Bikeinside** och tryck **⌘R**.
3. Godkänn Bluetooth-frågan första gången appen startar.
4. Gå till **Enheter**, tryck **Sök efter enheter** och anslut din trainer, ditt pulsband och så vidare.

Har du ingen trainer inkopplad kan du cykla med piltangenterna (↑/↓ ändrar den simulerade effekten).

## Funktioner

- **Tre världar** som genereras i kod: *Skogsslingan* (kuperad skog), *Sjörundan* (platt runda runt en insjö) och *Fjällvägen* (lång klättring upp mot kalfjället). Där finns granar, tallar, björkar, röda stugor med vita knutar och flaggstänger.
- **Realistisk fysik**: lutning, rullmotstånd, luftmotstånd (CdA räknas från längd och vikt), luftens densitet på höjd, rotationströghet och drafting.
- **Smart trainer via Bluetooth FTMS** med backsimulering (justerbar "trainerkänsla") och ERG-läge. Wattmätare (CPS), pulsband (HRS) och kadenssensorer (CSC) stöds också. Enheterna återansluts automatiskt.
- **12 träningspass**: återhämtning, distans, tempo, sweet spot, över–under, tröskel, VO2max, 30/30, sprinter, pyramid, **FTP-ramptest** och **20-minuterstest**. Det går också att importera `.erg`- och `.mrc`-filer.
- **Medcyklister** i fem tempogrupper som trycker på i backarna och som du kan ligga i draften bakom.
- **Segment**: klättringar och spurter tas med tid, och personbästa sparas.
- **Statistik**: NP, IF, TSS, tid i zoner och bästa effekt (5 s, 1 min, 5 min, 20 min).
- **Export** till `.fit`, som fungerar i Strava, Garmin Connect, TrainingPeaks och intervals.icu.
- Fem kameravinklar och en HUD med effektzoner, höjdprofil och ledartavla.

### Kortkommandon under åkning

| Tangent | Funktion |
|---|---|
| ↑ / ↓ | Simulerad effekt ±10 W (shift: ±50 W) |
| Mellanslag | Pausa / fortsätt |
| C, 1–5 | Kameravinklar |
| E | ERG på/av |
| + / − | Passintensitet ±5 % |
| N | Hoppa till nästa steg i passet |
| Esc | Avsluta åkningen |
| H | Visa kortkommandon |

## Arkitektur

```
BikeinsideCore/     Swift-paket utan UI (byggs och testas även på Linux)
  Physics/          kraftbalans, steady state, drafting
  Route/            banor: spline, höjdprofil, lutning, automatisk klättringsdetektering
  World/            terräng (avståndsfält, sjöar, fjäll), meshar, träd/hus, väg, ben-IK
  Sensors/          FTMS/CPS/HRS/CSC-parsers, sensorfusion, trainerstyrning (tillståndsmaskin)
  Workouts/         pass, passbibliotek, .erg/.mrc-import
  Ride/             åkmotor (fysik, bottar, segment, varv, inspelning), statistik
  Export/           FIT-kodare
Bikeinside/         macOS-appen (SwiftUI + SceneKit + CoreBluetooth)
```

All logik som går att testa ligger i `BikeinsideCore` och täcks av enhetstester:

```sh
cd BikeinsideCore && swift test
```

CI (GitHub Actions) kör testerna på Linux och macOS och bygger appen i både Debug och Release för varje push.

## Integritet

All data sparas lokalt i `~/Library/Application Support/Bikeinside`. Ingenting skickas någonstans.
