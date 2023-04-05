
# Change Log
All notable changes to this project will be documented in this file.
 
The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).
 
## [Unreleased] - yyyy-mm-dd

Here we write upgrading notes for brands. It's a team effort to make them as
straightforward as possible.

### Added

### Changed
- dependencies update

### Fixed
- Improved sync speed

## 2023-03-31_d8b27f7___2023-03-31_875d678

### Added
- Accept all invites in dialog
- Cargo room type
- Unique name constraint for Cargo rooms
- Checkpoints preset
- Cargo sync flow

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

