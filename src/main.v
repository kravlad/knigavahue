module main

import flag
import json
import math
import net.http
import os
import pcre
import regex
import term
import time

const user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36'
const base_url = 'https://knigavuhe.org/'

// Config holds configuration options for fetching and saving a book.
//
// Fields:
// - attempts: number of attempts to fetch data (default: 3)
// - delay: delay in seconds between requests (default: 5)
// - path: path to save the book
// - url: URL of the book
struct Config {
	attempts int = 3 @[short: a; xdoc: 'number of attempts to fetch data']
	delay    int = 5 @[short: d; xdoc: 'delay in seconds between requests']
mut:
	path string @[short: p; xdoc: 'path to save the book']
	url  string @[short: u; xdoc: 'URL of the book']
}

// new creates and initializes a new Config instance by parsing command line arguments.
// If required fields are missing, it prompts the user for input interactively.
// Validates the URL and path fields, ensuring the URL matches the expected base_url
// and the path is a valid directory. Exits the program with an error message if validation fails.
// Returns a reference to the populated Config struct.
fn Config.new() &Config {
	mut config, _ := flag.to_struct[Config](os.args, skip: 1) or {
		eprintln(term.red('error parsing command line arguments: ${err}'))
		Config{}, []string{}
	}

	if config.url == '' {
		config.url = os.input(term.ok_message('enter the URL of the book: '))
	}
	if config.url == '' {
		eprintln(term.red('no URL provided'))
		exit(1)
	}
	if !config.url.starts_with(base_url) {
		eprintln(term.red('invalid URL format. Please provide a valid URL'))
		exit(1)
	}

	path := os.getwd()
	if config.path == '' {
		config.path = os.input(term.ok_message('enter the path to save the book (default: "${path}"): '))
	}
	if config.path == '' {
		config.path = path
	} else if !os.is_dir(config.path) {
		eprintln(term.red('provided path is not a directory: ${config.path}'))
		exit(1)
	}
	return &config
}

// Book represents a book entity with various attributes such as genre, likes, favorites, and permissions.
// Fields:
// - id: Unique identifier for the book.
// - genre_id: Identifier for the genre of the book.
// - likes: Number of likes the book has received.
// - dislikes: Number of dislikes the book has received.
// - favs: Number of times the book has been favorited.
// - blocked: Indicates if the book is blocked.
// - liked: Indicates if the current user has liked the book (1 for liked, 0 otherwise).
// - favored: Indicates if the current user has favorited the book.
// - comments_allowed: Specifies if comments are allowed on the book.
// - likes_allowed: Specifies if likes are allowed on the book.
// - is_downloadable: Specifies if the book can be downloaded.
// - name: The title of the book (mutable).
// - chapters: List of chapters in the book (mutable).
struct Book {
	id               int
	genre_id         int
	likes            int
	dislikes         int
	favs             int
	blocked          bool
	liked            int
	favored          bool
	comments_allowed bool
	likes_allowed    bool
	is_downloadable  bool
mut:
	name     string
	chapters []Chapter
}

// from_html parses a Book object from the provided HTML string reference.
// It extracts the book's JSON data, chapter list, and book name using regular expressions,
// decodes the JSON into the Book and Chapter structures, and sanitizes the book name.
// Returns a reference to the populated Book object on success, or an error on failure.
//
// Arguments:
//   html (&string): Reference to the HTML content containing book data.
//
// Returns:
//   !&Book: Reference to the parsed Book object, or an error if extraction or parsing fails.
fn Book.from_html(html &string) !&Book {
	book_json := extract_data(html, r'.*cur\.book\s*=\s*(.*);.*') or {
		eprintln(term.red('failed to get book data: ${err}'))
		return err
	}
	mut book := json.decode(Book, book_json) or {
		eprintln(term.red('failed to parse json'))
		return err
	}

	chapters_json := extract_data(html, r'.*var\s*player\s*=\s*new\s*BookPlayer\([0-9]+,\s*(.*?),\s*\[\{"label":.*') or {
		eprintln(term.red('failed to get book data: ${err}'))
		return err
	}
	book.chapters = json.decode([]Chapter, chapters_json) or {
		eprintln(term.red('failed to parse json'))
		return err
	}

	book_name := extract_data(html, r'.*https://knigavuhe.org/book/(.*)/?.*') or {
		eprintln(term.red('failed to get book data: ${err}'))
		return err
	}
	book.name = sanitize_filename(book_name)
	return &book
}

// dump downloads all chapters of the Book using the provided HTTPClient and saves them as .mp3 files
// in a directory named after the book inside the specified path. Returns true if all chapters are
// successfully downloaded and saved, otherwise returns false. If an error occurs while creating the
// book directory or saving a chapter, the error is printed and the process continues with the next chapter.
// A delay is applied between chapter downloads as specified by the client.
fn (book &Book) dump(path string, client &HTTPClient) bool {
	book_path := mkdir(path, book.name) or {
		panic(term.red('error creating book directory: ${err}'))
	}

	mut errors := false
	for i, chapter in book.chapters {
		chapter_path := os.join_path(book_path, '${sanitize_filename(chapter.title)}.mp3')
		if os.exists(chapter_path) && os.file_size(chapter_path) > 0 {
			errors = true
			println(term.warn_message('file "${path}" already exists, skipping download'))
			continue
		}
		data := chapter.download(client) or {
			errors = true
			continue
		}
		create_file(chapter_path, data) or {
			errors = true
			eprintln(err)
			continue
		}

		if i < book.chapters.len - 1 {
			time.sleep(client.delay)
		}
	}
	return !errors
}

// Chapter represents a chapter entity with metadata and playback information.
// Fields:
// - id: Unique identifier for the chapter.
// - title: Title of the chapter.
// - url: URL associated with the chapter.
// - player_data: PlayerData struct containing playback-related data.
// - error: Error code or status for the chapter.
// - duration: Duration of the chapter in seconds (integer).
// - duration_float: Duration of the chapter in seconds (floating point).
struct Chapter {
	id             int
	title          string
	url            string
	player_data    PlayerData
	error          int
	duration       int
	duration_float f64
}

// download downloads the content of the chapter from the specified URL using the provided HTTP client.
// It prints status messages before and after the download attempt.
// Returns the downloaded bytes on success, or an error if the download fails.
fn (chapter &Chapter) download(client &HTTPClient) ![]u8 {
	println('\ndownloading file ${chapter.url} ...')
	resp := client.fetch(chapter.url) or {
		eprintln(term.red('failed to download chapter: ${err}'))
		return err
	}
	println('${chapter.url} successfully downloaded\n')
	return resp.bytes()
}

// PlayerData represents metadata for a media player item, including title, cover image,
// cover type, authors, readers, and series information.
struct PlayerData {
	title      string
	cover      string
	cover_type string
	authors    string
	readers    string
	series     string
}

// HTTPClient represents an HTTP client with configurable retry attempts, delay between retries, and a custom user agent.
//
// Fields:
// - attempts: The number of retry attempts for HTTP requests.
// - delay: The duration to wait between retry attempts.
// - user_agent: The User-Agent string to use in HTTP requests.
struct HTTPClient {
	attempts   int
	delay      time.Duration
	user_agent string
}

// make_request sends a GET HTTP request to the specified URL using the client's user agent.
// It returns the http.Response on success or an error otherwise.
//
// Parameters:
// - url: The URL to which the GET request will be sent.
//
// Returns:
// - http.Response: The response from the HTTP request.
// - error: An error if the request fails.
fn (client &HTTPClient) make_request(url string) !http.Response {
	mut req := http.new_request(.get, url, '')
	req.add_header(.user_agent, client.user_agent)
	return req.do()
}

// fetch attempts to retrieve the content from the specified `url` using the HTTP client.
// It retries the request up to `client.attempts` times, waiting for `client.delay` between attempts.
// If a request is successful and returns a 200 status code, a reference to the response body is returned.
// If all attempts fail, the last encountered error is returned.
//
// Parameters:
// - url: The URL to fetch data from.
//
// Returns:
// - A reference to the response body string on success.
// - An error if all attempts fail or a non-200 status code is received.
fn (client &HTTPClient) fetch(url string) !&string {
	mut er := error('')
	for i := 0; i < client.attempts; i++ {
		resp := client.make_request(url) or {
			eprintln(term.red('failed to fetch data from ${url}'))
			er = err
			time.sleep(client.delay)
			continue
		}
		if resp.status_code == 200 {
			return &resp.body
		}
		eprintln(term.red('failed to fetch data from ${url}, status code: ${resp.status_code}'))
		er = error('failed to fetch data from ${url}, status code: ${resp.status_code}')
		time.sleep(client.delay)
	}
	return er
}

// mkdir creates a new directory with the specified `dir` name inside the given `path`.
// If the directory already exists, it prints a warning and skips creation.
// Returns the full path to the created (or existing) directory on success, or an error on failure.
//
// Arguments:
// - path: The base path where the new directory should be created.
// - dir: The name of the directory to create.
//
// Returns:
// - string: The full path to the created or existing directory.
// - !: An error if the directory could not be created.
fn mkdir(path string, dir string) !string {
	new_path := os.join_path(path, dir)
	if !os.exists(new_path) {
		os.mkdir(new_path) or {
			eprintln(term.red('failed to create book directory: ${err}'))
			return err
		}
	} else {
		println(term.warn_message('directory "${dir}" already exists, skipping create'))
	}
	return new_path
}

// create_file creates a new file at the specified `path` and writes the provided `data` to it.
// Returns an error if:
// - `data` is empty,
// - the file already exists and is not empty,
// - the file cannot be created,
// - or writing to the file fails.
//
// Arguments:
// - path: the file system path where the file will be created.
// - data: the byte array to write to the file.
fn create_file(path string, data []u8) ! {
	if data.len == 0 {
		return error(term.red('failed to download file: ${path}'))
	}

	mut file := os.create(path) or { return error(term.red('failed to create file: ${err}')) }
	defer {
		file.close()
	}
	file.write(data) or { return error(term.red('failed to write to file: ${err}')) }
}

// extract_data searches the provided HTML string for a pattern specified by the query (regular expression).
// Returns the first captured group from the match if found.
// Uses PCRE for regex matching with case-insensitive flag.
// Returns an error if the regex compilation or matching fails.
//
// Arguments:
//   html  - reference to the HTML string to search
//   query - regular expression pattern to search for
//
// Returns:
//   string - the first captured group from the match
//   !      - error if regex compilation or matching fails
fn extract_data(html &string, query string) !string {
	re := pcre.new_regex(query, C.PCRE_CASELESS) or { panic(term.red(err.msg())) }
	defer {
		re.free()
	}
	matched := re.match_str(html, 0, 0) or { return err }
	return matched.get(1)
}

// sanitize_filename removes invalid characters from a filename string to ensure it is safe for use in filesystems.
// It replaces characters such as ':', '/', '<', '>', '"', '|', '?', and '*' with an empty string.
// The resulting string is trimmed to a maximum length of 252 characters and any leading or trailing spaces or dots are removed.
//
// Parameters:
//   text string - The input filename string to sanitize.
//
// Returns:
//   string - The sanitized filename string.
fn sanitize_filename(text string) string {
	mut re := regex.regex_opt(r'[:\/<>"|?*]') or { panic(term.red(err.msg())) }
	res := re.replace(text, '')
	return res[..math.min(res.len, 252)].trim(' .')
}

fn main() {
	config := Config.new()
	println(term.ok_message('\nnumber of attempts on error: ${config.attempts}\ndelay between requests: ${config.delay} sec\n'))
	client := HTTPClient{config.attempts, config.delay * time.second, user_agent}
	html := client.fetch(config.url) or { panic(term.red('error fetching HTML: ${err}')) }
	book := Book.from_html(html) or { panic(term.red('error parsing book data: ${err}')) }
	if book.dump(config.path, &client) {
		println(term.ok_message('book "${book.name}" was been successfully dumped'))
	}
}
