KPSS Study Assistant

KPSS Study Assistant is a comprehensive iOS application architected to support candidates preparing for the Public Personnel Selection Examination (KPSS) in Turkey. It functions as a personalized digital coach, integrating subject tracking, dynamic video content delivery via YouTube Data API v3, an interactive flashcard system for active recall, and advanced performance analytics powered by Swift Charts.

Key Features

Intelligent Subject Management

Progress Tracking: Monitor completion rates across core disciplines including Turkish, Mathematics, History, Geography, and Citizenship.

Study Planner: Schedule study sessions with specific dates and times.

Automated Notifications: Receive timely reminders one hour prior to scheduled study sessions to ensure consistency.

Dynamic Video Integration

YouTube Data API v3 Implementation: Seamlessly fetches and updates video content from curated playlists.

Simulated Updates: Features an intelligent simulation mechanism to reflect new content uploads, maintaining user engagement.

Metadata Display: Presents comprehensive video details including titles, thumbnails, and durations directly within the application interface.

Watch History: Tracks viewing progress to manage course completion effectively.

Interactive Flashcard System

Active Recall Methodology: Utilizes a swipe-based interface (right for correct, left for incorrect) to facilitate efficient learning.

Curated Question Bank: Includes a database of high-yield questions relevant to the examination curriculum.

Instant Feedback Loop: Provides immediate detailed explanations for incorrect responses, reinforcing correct information.

Advanced Analytics Dashboard

Data Visualization: Leverages the Swift Charts framework to render intuitive graphs representing subject mastery and study patterns.

Countdown Timer: Displays a real-time countdown to the examination date, enhancing time management awareness.

Profile Customization: Allows users to manage personal profiles, including department selection and avatar customization.

Technical Stack

Language: Swift 5

UI Framework: SwiftUI

Networking: URLSession & YouTube Data API v3

Data Persistence: UserDefaults

Charts: Swift Charts Framework

Concurrency: Async/Await & Combine

Installation

Clone the repository:

git clone [https://github.com/semihatiik/KPSS-Study-Assistant-iOS.git](https://github.com/semihatiik/KPSS-Study-Assistant-iOS.git)


Open KPSSAsistanim.xcodeproj in Xcode.

Configuration: You must configure your own YouTube Data API Key in ContentView.swift to enable video fetching capabilities:

let YOUTUBE_API_KEY = "YOUR_API_KEY_HERE"


Build and run on a simulator or physical device (Requires iOS 16.0 or later).

Contributing

contributions to the open-source community are welcome. To contribute to this project:

Fork the Project

Create your Feature Branch (git checkout -b feature/NewFeature)

Commit your Changes (git commit -m 'Add NewFeature')

Push to the Branch (git push origin feature/NewFeature)

Open a Pull Request

License

This project is licensed under the MIT License. See the LICENSE file for details.

Author

Semih Atik

GitHub: @semihatiik

Designed and developed to empower students in their academic journey.
