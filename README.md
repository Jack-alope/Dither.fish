# Dither.fish

> Smart gear management and trip planning for backpackers.

**Dither.fish** is a free, open-source web and iOS app that helps you manage your gear, plan trips, and track pack weight — down to the gram.

🌐 **[dither.fish](https://dither.fish)** · ☕ **[Buy me a coffee](https://buymeacoffee.com/mrph)**

---

## Features

- **Gear Locker** — store your entire kit with name, brand, category, weight, and quantity. Filter and search instantly.
- **Bundles** — group gear that travels together (shelter system, sleep kit, cook setup) and add the whole bundle to a pack in one action.
- **Trip Planning** — create trips with multiple packs. Organise gear into cubes, check items off as you pack, and see weight broken down by base, worn, and consumable.
- **Weight Tracking** — live totals per pack and per trip. Visual weight bar so you always know where the grams are going.
- **Gear Catalog** — browse community-curated gear with verified weights. Add items straight to your locker.
- **Trip Archives** — archive completed trips with a frozen snapshot of your gear so you always have a record of exactly what you carried.
- **Offline-first iOS app** — changes queue locally when you're out of signal and sync automatically when you reconnect.

---

## Stack

| Layer | Tech |
|---|---|
| Server | Node.js · Express · MongoDB (Mongoose) |
| Web frontend | Vanilla JS · CSS (no framework) |
| iOS app | SwiftUI · Swift 5.9+ |
| Auth | JWT (bcryptjs) |
| Hosting | Railway |

---

## Getting started (local development)

### Prerequisites

- Node.js 18+
- A MongoDB instance (local or [MongoDB Atlas](https://www.mongodb.com/atlas))

### 1. Clone the repo

```bash
git clone https://github.com/Jack-alope/Dither.fish.git
cd Dither.fish
```

### 2. Configure environment

Create a `.env` file in the project root:

```env
MONGODB_URI=your_mongodb_connection_string
JWT_SECRET=your_secret_key
PORT=3000
```

### 3. Install dependencies and run

```bash
cd server
npm install
node index.js
```

Open [http://localhost:3000](http://localhost:3000).

### iOS app

Open `ios/Dither/Dither.xcodeproj` in Xcode 15+, select a simulator or device, and hit Run. The app points to `https://dither.fish` by default — update `APIService.swift` to point to your local server if needed.

---

## Project structure

```
Dither.fish/
├── server/              # Express API
│   ├── index.js         # Entry point
│   ├── models/          # Mongoose schemas (Gear, Bundle, Trip, User, Catalog)
│   ├── routes/          # API routes (auth, gear, bundles, trips, catalog)
│   └── middleware/      # JWT auth middleware
├── ios/Dither/          # SwiftUI iOS app
│   └── Dither/
│       ├── AppState.swift       # Global state + offline queue
│       ├── APIService.swift     # Network layer
│       ├── Models.swift         # Codable data models
│       ├── OfflineQueue.swift   # Offline sync infrastructure
│       └── *View.swift          # Feature views
├── index.html           # Web app shell + landing page
├── app.js               # Web app logic
├── style.css            # Styles
└── favicons/            # Icons and wordmark
```

---

## Contributing

Pull requests are welcome. For larger changes, open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a PR against `main`

---

## License

MIT — see [LICENSE](LICENSE) for details.
