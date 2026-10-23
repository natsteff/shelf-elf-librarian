import Foundation

public enum StarterDescriptions {
    public static let introduction = "This is an optional, recommended starter profile for organizing your library. You can modify or delete it to suit your needs, or create additional profiles with your own settings and organization."
    private static let descriptions: [String: (Kind, String)] = [
        "Video Media Server": (.video, """
        Organize movies, TV episodes, documentaries, commercials, home videos and music videos. Use filename patterns to identify components and assign a Video Type, then choose a folder layout for each type.

        Suggested organization: Movies/Title (Year) and TV Shows/Series/Season 01. Review Type, episode numbers and titles before filing. Multiple types can share a destination folder.
        """),
        "Music": (.music, """
        Clean and organize individual tracks, albums and live recordings using Artist, Album, Title, Track Number, Year and Genre. Optional artist buckets divide larger collections into A–Z, number and symbol folders.

        Suggested organization: Artist/Album, or Genre/Artist/Album if genre is important to your collection. Use universal exceptions for artist names with unusual spelling or capitalization. Components come from filenames or manual entry. Use the tag icon to inspect MP3 tags as read-only reference information; tags never automatically change components or proposed names.
        """),
        "Audiobooks": (.audiobook, """
        Organize audiobooks by full author name, optional series and book title. Keep Series Number separate from Chapter Number so numbered books and their individual chapters remain correctly grouped.

        Suggested organization: Author/Series/02 - Book Title, or Author/Book Title for standalone books. Enable parent-folder patterns when your existing folders reliably identify author, series and book. Review chapter numbers before filing multi-file books.
        """),
        "FORGE": (.documents, """
        Organize a primarily PDF library for FORGE GameSheets (https://github.com/natsteff/forge-gamesheets), using one first-level folder per game and descriptive resource filenames.

        The related github entry states that FORGE GameSheets is a self-hosted home for printable game resources, custom GameSheets, and temporary live scoring. Organize and search PDF rulebooks, score sheets, player aids, and print-and-play files; design new structured sheets; and share compatible sheets as interactive LiveSheets across devices. Source PDFs remain yours and are not modified by the application.

        Suggested Shelf Elf organization: interpret {GameTitle} - {ResourceName}, file into {GameTitle}, and retain {GameTitle} - {ResourceName} as the filename. For example: Yahtzee/Yahtzee - Score Sheet.pdf. Use consistent game names across related resources. Shelf Elf prepares the library’s names and folders; FORGE provides the browsing, design and LiveSheet features described above.
        """),
        "ROMs": (.roms, """
        Organize video game ROMs and disc images by their target system, with optional Region, Edition and Revision components. Extension mappings infer clear systems such as .nes → NES and .gba → Game Boy Advance. Shared extensions need System from filename/parent-folder patterns or manual selection. System aliases standardize labels for the same platform.

        Suggested organization: System/original ROM filename. Original filenames are preserved. Folders containing disc descriptors or playlists require complete-set handling and are blocked from individual filing. Preserve region, language and revision identifiers when they distinguish releases. Use separate profiles for collections with different naming conventions, and review ambiguous system assignments before filing.
        """),
        "Photos": (.photos, """
        Organize image files using descriptive titles, dates and events captured from filenames or entered manually.

        Suggested organization: DateTaken/Event, such as 2026-10-21/Family Gathering. Keep camera-generated names when they help identify originals, or use a consistent date-and-title filename pattern. Date Taken currently comes from filename patterns or manual entry; embedded photo metadata is not read.
        """),
        "PDF Library": (.documents, """
        Clean and organize general PDF documents, references, manuals and reports using Title, Date, Revision and any additional components captured by your patterns.

        Suggested organization: use separate profiles for subjects or collections with different layouts. Include dates or revisions in filenames when multiple editions need to coexist. Use the Books & Comics profile when Author, Series and Book Title are a better fit.
        """),
        "Software & Installers": (.software, """
        Organize installer files and software archives using Product, Version, Platform and Architecture components captured from filenames or entered manually. This profile also suits installable PC game packages.

        Suggested organization: Product/Version or Platform/Product. Preserve version numbers and architecture labels so different installers remain distinguishable. Keep the original filename when it contains useful release details. Application bundles are not treated as ordinary installer files.
        """),
        "Ebooks & Comics": (.audiobook, """
        Organize ebooks and comics by Author, optional Series and Book Title, with Publisher, Year, Illustrator, Issue Number and Volume available when needed. Choose the appropriate book subtype to show relevant components.

        Suggested organization: Author/Series/02 - Book Title for books, or Series/Volume for comics. Consider separate ebook and comic profiles when their layouts differ substantially. Preserve issue numbers, editions and credited names that distinguish items.
        """)
    ]
    public static func fillingBlankNotes(_ profile: Profile) -> Profile {
        guard profile.notes == nil,
              let (kind, body) = descriptions[profile.name], kind == profile.kind else { return profile }
        var result = profile
        result.notes = introduction + "\n\n" + body
        return result
    }
}
