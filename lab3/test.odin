#+feature global-context
package main

import "base:builtin"
import "base:runtime"
import "core:fmt"
import "core:hash/xxhash"
import "core:log"
import "core:mem"
import "core:net"
import "core:os"
import "core:os/os2"
import "core:slice"
import "core:strconv"
import str "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import http "odin-http"


@(test)
test_test :: proc(_: ^testing.T) {
	fmt.println("Nothing test passed")
}
