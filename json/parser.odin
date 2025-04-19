package json

import "core:fmt"
import "core:os"
import "core:strconv"

// example:
// import "json"
// main :: proc() {
// 
//     data, ok := os.read_entire_file("test.json")
//     if !ok {return}
//     defer delete(data)
// 
// 
//     v, ok2 := json.parse(data[:])
//     if ok2 {
//         …
//     } else {
//         fmt.println("can't parse")
//     }
// 
// }

Token_Type :: enum {
    NULL,
    GARBAGE,
    COMMA,
    COLLON,
    OBJECT_START,
    OBJECT_END,
    ARRAY_START,
    ARRAY_END,
    NUMBER,
    STRING,
    TRUE,
    FALSE,
}

Token :: struct {
    type:     Token_Type,
    line:     int,
    position: int,
    data:     string,
}

Null :: struct {}

JSON_Error :: distinct string

Value :: union {
    string,
    f64,
    map[string]Value,
    [dynamic]Value,
    bool,
    Null,
    JSON_Error,
}


parse :: proc(data: []u8) -> (Value, bool) {
    if len(data) == 0 {return Null{}, false}
    tokens: [dynamic]Token

    // Tokenize
    {
        current_idx := 0
        current_n := 0
        current_line := 1
        for current_idx := 0; current_idx < len(data); current_idx += 1 {
            switch rune(data[current_idx]) {
            case '{':
                append(&tokens, Token{.OBJECT_START, current_line, current_n, "{"})
                current_n += 1
            case '}':
                append(&tokens, Token{.OBJECT_END, current_line, current_n, "}"})
                current_n += 1
            case '[':
                append(&tokens, Token{.ARRAY_START, current_line, current_n, "["})
                current_n += 1
            case ']':
                append(&tokens, Token{.ARRAY_END, current_line, current_n, "]"})
                current_n += 1
            case ':':
                append(&tokens, Token{.COLLON, current_line, current_n, ":"})
                current_n += 1
            case ',':
                append(&tokens, Token{.COMMA, current_line, current_n, ","})
                current_n += 1
            case 't':
                str := string(data[current_idx:current_idx + 4])
                if str == "true" {
                    append(&tokens, Token{.TRUE, current_line, current_n, "true"})
                    current_n += 4
                    current_idx += 3
                } else {
                    fmt.eprintln("error, unknown 't'", current_line, current_n)
                    return Null{}, false
                }
            case 'f':
                str := string(data[current_idx:current_idx + 5])
                if str == "false" {
                    append(&tokens, Token{.FALSE, current_line, current_n, "false"})
                    current_n += 5
                    current_idx += 4
                } else {
                    fmt.eprintln("error, unknown 'f'", current_line, current_n)
                    return Null{}, false
                }
            case 'n':
                str := string(data[current_idx:current_idx + 4])
                if str == "null" {
                    append(&tokens, Token{.NULL, current_line, current_n, "null"})
                    current_n += 4
                    current_idx += 3
                } else {
                    fmt.eprintln("error, unknown 'n'", current_line, current_n)
                    return Null{}, false
                }
            case ' ', '\t':
                current_n += 1
            case '\n':
                current_n = 0
                current_line += 1
            case '"':
                for b, i in data[current_idx + 1:] {
                    if b == '"' && data[current_idx + i] != '\\' {
                        append(
                            &tokens,
                            Token {
                                type = .STRING,
                                line = current_line,
                                data = string(data[current_idx:current_idx + i + 2]),
                            },
                        )
                        current_idx += i + 1
                        current_n += i + 1
                        break

                    }
                }
            case '-', '0' ..= '9':
                str, n, ok := take(
                    data,
                    current_idx,
                    []u8 {
                        '0',
                        '1',
                        '2',
                        '3',
                        '4',
                        '5',
                        '6',
                        '7',
                        '8',
                        '9',
                        '.',
                        'e',
                        'E',
                        '+',
                        '-',
                    },
                )
                if ok {
                    append(&tokens, Token{type = .NUMBER, line = current_line, data = str})
                    current_idx += n
                    current_n += n
                } else {
                    fmt.eprintln("Error", current_line, str)
                }
            case:
                fmt.println(current_idx, rune(data[current_idx]))
                append(
                    &tokens,
                    Token {
                        type = .GARBAGE,
                        line = current_line,
                        data = string(data[current_idx:current_idx + 1]),
                    },
                )
            }

            current_n += 1
        }
    }

    // parse tokens
    v, i, ok := parse_token(tokens[:], 0)
    return v, ok
}

parse_token :: proc(tokens: []Token, current_: int) -> (Value, int, bool) {
    current := current_

    token := tokens[current]

    #partial switch token.type {
    case .OBJECT_START:
        current += 1
        obj: map[string]Value
        consumed_tokens := 0
        for tokens[current].type != .OBJECT_END && current < len(tokens) - 2 {
            if tokens[current].type == .STRING && tokens[current + 1].type == .COLLON {
                key, _, ok := parse_token(tokens, current)
                if !ok {
                    fmt.eprintln("Error key")
                }
                value, n, ok2 := parse_token(tokens, current + 2)
                if !ok2 {
                    fmt.eprintln("Error value")
                }
                obj[key.(string)] = value
                consumed_tokens += 1 + 1 + n // string, colon and value length
                current += 1 + 1 + n

                // handle commas
                {
                    // TODO: check if comma is valid/necessary
                    if tokens[current].type == .COMMA {
                        consumed_tokens += 1
                        current += 1
                    }
                }
            } else {
                fmt.eprintln("error object broken?", current, consumed_tokens, len(tokens))
                fmt.eprintln(tokens[current])
                return obj, consumed_tokens, false
            }
        }
        if tokens[current].type == .OBJECT_END {
            consumed_tokens += 1
            current += 1
            if current < len(tokens) && tokens[current].type == .COMMA {
                consumed_tokens += 1
                current += 1
            }
        }
        return obj, consumed_tokens, true
    case .ARRAY_START:
        arr: [dynamic]Value
        // value and , or ]
        current += 1
        for i := current; i < len(tokens) - 1; i += 2 {
            v, n, ok := parse_token(tokens, i)
            if !ok {
                fmt.eprintln("Error array value")
            }
            append(&arr, v)
            if tokens[i + 1].type == .ARRAY_END {
                return arr, i - current + 3, true
            } else if tokens[i + 1].type == .COMMA {
                // good
            } else {
                fmt.eprintln("array error no comma")
                return arr, 0, false
            }
        }
        return arr, 0, false

    case .NUMBER:
        v, ok := strconv.parse_f64(token.data)
        if ok {
            return v, 1, ok
        }
        return 0, 0, false
    case .TRUE:
        return true, 1, true
    case .FALSE:
        return false, 1, true
    case .NULL:
        return Null{}, 1, true
    case .STRING:
        return string(token.data[1:len(token.data) - 1]), 1, true
    case .GARBAGE:
        return JSON_Error("garbage"), 1, false

    }

    return Null{}, 0, false
}

take :: proc(data: []u8, start: int, symbols: []u8) -> (string, int, bool) {
    for b, i in data[start + 1:] {
        valid := false
        for s in symbols {
            if b == s {
                valid = true
                break
            }
        }
        if !valid {
            end := start + i + 1
            return string(data[start:end]), end - start - 1, true
        }
    }
    return "", -1, false
}
