
# Change Log
All notable changes to this project will be documented in this file.
 
The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).
 
## [Unreleased] - yyyy-mm-dd

Here we write upgrading notes for brands. It's a team effort to make them as
straightforward as possible.

### Added

### Changed
- Refactored communication between chat and platform during onliners sync
- Continuous backup
- Main and backup drives are interchangeable
- Unplugging main while backup is in makes backup the main drive

### Fixed
- File download
- gallery url fix
- File corruption during sync

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
