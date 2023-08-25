# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased] - yyyy-mm-dd

Here we write upgrading notes for brands. It's a team effort to make them as
straightforward as possible.

### Added
- concurrent cargo sensors
- firmware upgrade

### Changed
- extend cargo checkpoints
- update cargo indication docs
- await full file [#456]

### Fixed
- pause uploads when uploader is busy (IMPROVED)
- cargo user invitation [#460]


## 2023-08-11_279815b___2023-08-11_24d6bac

### Added
- Filesystem optimization
- Router support
- Upload by Drag&Drop to chats/rooms
- chat links
- Import and backup cargo user keys

### Changed
- more logs on copying w/ progress

### Fixed
- force image loading in chat
- set correct documentation link for cargo scenario
- Half-uploaded files bug
- force video loading in chat
- extra invites for checkpoints into cargo room
- cargo camera sensor input stability
- pause uploads when uploader is busy
- copying hangups

## 2023-06-30_ad580b9___2023-06-29_6ab0603

### Added

- extend cargo settings (camera sensors && weight sensor)
- concurrent copying tracking
- Add cargo user to set cargo sensor settings
- room invite lookup for cargo user
- write data from camera sensors into the cargo room
- add Led indication for cargo scenario && docs
- Add CPU temperature & utilization metrics to the dashboard
- ONVIF camera support


### Changed

- more copying and changetracker logging
- file chunk upload awaits a file on FS
- faster restart of supervision
- support cargo camera url from chat
- minimise cargo scope
- include OS data page in the dashboard

### Fixed

- uploader background breaking the page when leaving room
- copying stuck
- backup stuck on ejecting drive while copying
- set correct input of room invite lookup for cargo user
- add FileIndex for file created in the cargo room
- onliners and cargo fix on drive ejecting
- cargo settings compatibility w/ previous version
- fix supervision restarts


## 2023-05-22_3fefe32___2023-05-24_98fba24

### Added

- control the impendance of GPIO24

### Changed

### Fixed

- broken file message display
- fix room displaying w/o pub_key
- fs listing (broken synchronization) + testing
- Update users/rooms cache on USB plugging/unplugging

## 2023-05-17_f2cf2cc___2023-05-18_ccb67a5

### Added

- Social Sharing. filter out bad parts
- Filesystem based files synchronization

### Changed

### Fixed

- Too long buttons on mobile
- scroll uploads to top on uploader mount
- uploads color changing depending on room/chat belonging
- FS healer fix and use it for all but cargo
- cargo copying after main data write

## 2023-05-12_7e5fcce___2023-05-12_b47aebb

### Added

- Social Sharing. key recover check
- Recover key from Social Sharing
- ChangeTracker. log long expiration keys
- Progress bar for dump
- AdminDb placeholders

### Changed

- copying speed optimization

### Fixed

- large filename in dump statistic
- Admin panel Wifi rename

## 2023-05-01_344a783___2023-05-03_059ad40

### Added

- free spaces on admin panel
- Store key using Social Sharing
- Ability to trigger Cargo sync again
- Prevent DB directory from being renamed

### Changed

- Separate main from backup DB
- Configurable continuous backup
- styles for dark theme

### Fixed

- visit admin panel from room_invite message
- added scroll for admin room and mobile markup fixed
- Cargo sync and USB Drive dump bar scrolling away with the room content
- Cargo sync and USB Drive dump not terminating when the drive is ejected
- Invite list during room switch
- Change Tracker expiry and nil values tracking

## 2023-04-26_e311fc1___2023-04-26_217f745

### Added

- USB drive dump progress
- Ability to resume failed drive dump
- AdminDb structure documentation

### Changed

- Hide Cargo sync timer and increase the timeout to 5 minutes
- ChangeTracker expiry
- searchbar color changed

### Fixed

- feeds close error on mobile bugfix
- message select checkbox bugfix
- text message editing bugfix
- Backup key password validation bugfix
- Cargo sync failing after 1 minute mark
- Dumping duplicate files
- Drive dump failing after 1 minute mark
- Adaptive uploads and users/rooms list for desctop
- Show Cargo Room tab regardless of media settings
- Error entering room on main drive fix
- Markup for admin room fixed
- Adaptive uploads and users/rooms list for mobile
- handle lost messages when viewing gallery

## 2023-04-15_c77d709___2023-04-15_64148f8

### Added

- Search box for users/rooms
- Users/Rooms sync optimization for UI
- Integration of Secret Sharing with encryption layer (#251)
- added shortcode for FE
- USB drive dump

### Changed

- short code to be first 6 hex digits (was 8)
- landing page code updated

### Fixed

- better broken files handling
- db changes tracking improvement

## 2023-04-07_a41ea0d___2023-04-07_c06e36f

### Added

- queue uploaded file chunks (improves stability)

### Changed

- dependencies update
- updating feed rendering w/ new mechanics
- Cargo room disappears after ejecting USB drive

### Fixed

- Improved sync speed
- Fixed cargo room crashing when it's not set
- Improved cargo styling
- Prevent backup/sync from corruption
- admin panel w/o login returns to login form (when page gets reconnected in admin panel)
- broken image render
- fix copying process

## 2023-03-31_d8b27f7___2023-03-31_875d678

### Added

- Accept all invites in dialog
- Cargo room type
- Unique name constraint for Cargo rooms
- Checkpoints preset
- Cargo sync flow
- Room post permanent link feature

### Changed

- uploading in one thread

### Fixed

- UI: uploads scroll to top on uploader mount
- submitting of edited message by keyword

## 2023-03-22_4082136___2023-03-23_e2c9aa8

### Added

- Cargo DB sync
- Naive API initial endpoints

### Changed

- mirroring mechanics

### Fixed

- file absence ignoring
- fix read only mode

## 2023-03-17_4ed6f98___2023-03-17_191b7bc

### Changed

- Refactored communication between chat and platform during onliners sync
- Continuous backup
- Main and backup drives are interchangeable
- Unplugging main while backup is in makes backup the main drive

### Fixed

- File download
- gallery url fix
- File corruption during sync
- markup breaking when key name is long

## 2023-03-11_2200db4___2023-03-11_acb5424

### Added

- extra front end encryption check

### Changed

- UI: audio button moved into paperclip menu
- `Chat.Db.BackupDbSupervisor` now receives the name of the DB it needs to supervise as an argument

### Fixed

- UI: uploader covering chat/room list
- lost feed names
- admin room user actions




