# knigavahue

**knigavahue** is a command-line tool for downloading audiobooks from [knigavuhe.org](https://knigavuhe.org/), written in V.

## Features

- Downloads all chapters of a book as `.mp3` files
- Organizes chapters into a directory named after the book
- Handles invalid filename characters and trims names for filesystem safety
- Retries failed downloads with configurable attempts and delay
- Interactive prompts for missing configuration

## Requirements

- [V language](https://vlang.io/) (latest stable version)
- Internet connection

## Installation

1. Clone the repository:

   ```sh
   git clone https://github.com/kravlad/knigavahue
   cd knigavahue
   ```

2. Install dependencies:

    ```sh
    v install
    ```

3. Build the project:

   ```sh
   v -prod src/main.v -o bin/kva
   ```

## Usage

```sh
./bin/kva -u <book_url> [-p <output_path>] [-a <attempts>] [-d <delay_seconds>]
```

- `-u` or `--url`: URL of the book on knigavuhe.org (required)
- `-p` or `--path`: Directory to save the book (optional, defaults to current directory)
- `-a` or `--attempts`: Number of download attempts per file (default: 3)
- `-d` or `--delay`: Delay in seconds between attempts (default: 5)

or just

```sh
./bin/kva
```

If any required argument is missing, the program will prompt for it interactively.

### Example

```sh
./bin/kva -u https://knigavuhe.org/book/6885-burja-mechejj/
```

## Project Structure

```
src/                # Source code
  main.v            # Main application code
  main_test.v       # Unit tests
```

## Dependencies

[pcre](https://github.com/vlang/pcre/) — for extracting data from HTML using regular expressions

## Testing

Run all tests with:

```sh
v test src/
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

## Disclaimer

This tool is for educational purposes only. Please respect the terms of service of knigavuhe.org and do not use this tool for unauthorized downloading or distribution of copyrighted material.
