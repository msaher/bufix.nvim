local rules = require("doit.rules")
local busted = require("plenary.busted")


-- TODO: use vim.tbl_equal instead
local function tbl_equal(a, b)
    if a == b then return true end

    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    for k, v in pairs(a) do
        if type(v) == "table" then
            if not tbl_equal(v, b[k]) then
                return false
            end
        else
            if v ~= b[k] then
                return false
            end
        end
    end

    -- make "a" has all keys "b" has
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
end


busted.describe("error patterns", function()

    local cases = {
        { rule = "absoft", line = "Error on line 3 of t.f: Execution error unclassifiable statement", want = {line = 3, filename = "t.f" }},
        { rule = "absoft", line = "Line 45 of \"foo.c\": bloofle undefined", want = {line = 45, filename = "foo.c" }},
        { rule = "absoft", line = "error on line 19 of fplot.f: spelling error?", want = {line = 19, filename = "fplot.f" }},
        { rule = "absoft", line = "warning on line 17 of fplot.f: data type is undefined for variable d", want = {line = 17, filename = "fplot.f" }},

        { rule = "ada", line = "foo.adb:61:11:  [...] in call to size declared at foo.ads:11", want = {line = 11, filename = "foo.ads"}},
        { rule = "ada", line = "0x8008621 main+16 at error.c:17", want = { line = 17, filename = "error.c" }},

        { rule = "aix", line = "****** Error number 140 in line 8 of file errors.c ******", want = {line = 8, filename = "errors.c"}},

        { rule = "ant",  line = "[javac] /src/DataBaseTestCase.java:27: unreported exception ...", want = {line = 27, filename = "/src/DataBaseTestCase.java"}},
        { rule = "ant",  line = "[javac] /src/DataBaseTestCase.java:49: warning: finally clause cannot complete normally", want = {line = 49, filename = "/src/DataBaseTestCase.java", type = "warning"}},
        { rule = "ant",  line = "[jikes]  foo.java:3:5:7:9: blah blah", want = {col = 5, col_end = 9, line = 3, line_end = 7, filename = "foo.java"}},
        { rule = "ant",  line = "[javac] c:/cygwin/Test.java:12: error: foo: bar", want = {line = 12, filename = "c:/cygwin/Test.java"}},
        { rule = "ant",  line = "[javac] c:\\cygwin\\Test.java:87: error: foo: bar", want = {line = 87, filename = "c:\\cygwin\\Test.java"}},
        -- -- Checkstyle error, but ant reports a warning (note additional
        -- -- severity level after task name)
        {rule = "ant", line = "[checkstyle] [ERROR] /src/Test.java:38: warning: foo", want = {line = 38, filename = "/src/Test.java", type = "warning"}},

        {rule = "bash", line = "a.sh: line 1: ls-l: command not found", want = {line = 1, filename = "a.sh"}},

        { rule = "borland", line = "Error ping.c 15: Unable to open include file 'sys/types.h'", want = {line = 15, filename = "ping.c"}},
        { rule = "borland", line = "Warning pong.c 68: Call to function 'func' with no prototype",  want = {line = 68, filename = "pong.c", type = "warning"}},
        { rule = "borland", line = "Error E2010 ping.c 15: Unable to open include file 'sys/types.h'",  want = {line = 15, filename = "ping.c"}},
        { rule = "borland", line = "Warning W1022 pong.c 68: Call to function 'func' with no prototype",  want = {line = 68, filename = "pong.c", type = "warning"}},

        { rule = "python_tracebacks_and_caml", line = "File \"foobar.ml\", lines 5-8, characters 20-155: blah blah", want = {col = 20, col_end = 155, line = 5, line_end = 8, filename = "foobar.ml"}},
        { rule = "python_tracebacks_and_caml", line = "File \"F:\\ocaml\\sorting.ml\", line 65, characters 2-145:\nWarning 26: unused variable equ.", want = {col = 2, col_end = 145, line = 65, filename = "F:\\ocaml\\sorting.ml"}},
        { rule = "python_tracebacks_and_caml", line = "File \"/usr/share/gdesklets/display/TargetGauge.py\", line 41, in add_children", want = {line = 41, filename = "/usr/share/gdesklets/display/TargetGauge.py"}},
        { rule = "python_tracebacks_and_caml", line = "File \\lib\\python\\Products\\PythonScripts\\PythonScript.py, line 302, in _exec", want = {line = 302, filename = "\\lib\\python\\Products\\PythonScripts\\PythonScript.py"}},
        { rule = "python_tracebacks_and_caml", line = "File \"/tmp/foo.py\", line 10", want = {line = 10, filename = "/tmp/foo.py"}},

        { rule = "cmake", line = "CMake Error at CMakeLists.txt:23 (hurz):", want = {line = 23, filename = "CMakeLists.txt"}},
        { rule = "cmake", line = "CMake Warning at cmake/modules/UseUG.cmake:73 (find_package):", want = {line = 73, filename = "cmake/modules/UseUG.cmake", type = "warning"}},

        { rule = "cmake_info", line = "  cmake/modules/DuneGridMacros.cmake:19 (include)", want = {line = 19, filename = "cmake/modules/DuneGridMacros.cmake", type = "info"}},

        { rule = "comma", line = "\"foo.f\", line 3: Error: syntax error near end of statement", want = {line = 3, filename = "foo.f"}},
        { rule = "comma", line = "\"vvouch.c\", line 19.5: 1506-046 (S) Syntax error.", want = {col = 5, line = 19, filename = "vvouch.c"}},
        { rule = "comma", line = "\"foo.c\", line 32 pos 1; (E) syntax error; unexpected symbol: \"lossage\"",  want = {col = 1, line = 32, filename = "foo.c"}},
        { rule = "comma", line = "\"foo.adb\", line 2(11): warning: file name does not match ...", want = {col = 11, line = 2, filename = "foo.adb", type = "warning"}},
        { rule = "comma", line = "\"src/swapping.c\", line 30.34: 1506-342 (W) \"/*\" detected in comment.", want = {col = 34, line = 30, filename = "src/swapping.c"}},

        { rule = "msft", line = "keyboard handler.c(537) : warning C4005: 'min' : macro redefinition", want = {line = 537, filename = "keyboard handler.c", type = "warning"}},
        { rule = "msft", line = "d:\\tmp\\test.c(23) : error C2143: syntax error : missing ';' before 'if'", want = {line = 23, filename = "d:\\tmp\\test.c"}},
        { rule = "msft", line = "d:\\tmp\\test.c(1145) : see declaration of 'nsRefPtr'", want = {line = 1145, filename = "d:\\tmp\\test.c"}},
        { rule = "msft", line = "1>test_main.cpp(29): error C2144: syntax error : 'int' should be preceded by ';'", want = {line = 29, filename = "test_main.cpp"}},
        { rule = "msft", line = "1>test_main.cpp(29): error C4430: missing type specifier - int assumed. Note: C++ does not support default-int", want = {line = 29, filename = "test_main.cpp"}},
        { rule = "msft", line = "C:\\tmp\\test.cpp(101,11): error C4101: 'bias0123': unreferenced local variable [C:\\tmp\\project.vcxproj]", want = {col = 11, line = 101, filename = "C:\\tmp\\test.cpp"}},

        { rule = "edg_1", line = "build/intel/debug/../../../struct.cpp(42): error: identifier \"foo\" is undefined", want = {line = 42, filename = "build/intel/debug/../../../struct.cpp"}},
        { rule = "edg_1", line = "build/intel/debug/struct.cpp(44): warning #1011: missing return statement at end of", want = {line = 44, filename = "build/intel/debug/struct.cpp", type = "warning"}},
        { rule = "edg_1", line = "build/intel/debug/iptr.h(302): remark #981: operands are evaluated in unspecified order", want = {line = 302, filename = "build/intel/debug/iptr.h", type = "info"}},

        { rule = "edg_2",  line = "detected during ... at line 62 of \"build/intel/debug/../../../trace.h\"", want = {line = 62, filename = "build/intel/debug/../../../trace.h"}},

        { rule = "epc", line = "Error 24 at (2:progran.f90) : syntax error", want = {line = 2, filename = "progran.f90"}},

        { rule = "ftnchek", line = "Dummy arg W in module SUBA line 8 file arrayclash.f is array", want = {line = 8, filename = "arrayclash.f"}},
        { rule = "ftnchek", line = "L4 used at line 55 file test/assign.f; never set", want = {line =55, filename = "test/assign.f"}},
        { rule = "ftnchek", line = "Warning near line 10 file arrayclash.f: Module contains no executable", want = {line = 10, filename = "arrayclash.f", type = "warning"}},
        { rule = "ftnchek", line = "Nonportable usage near line 31 col 9 file assign.f: mixed default and explicit", want = {col = 9, line = 31, filename = "assign.f"}},


        { rule = "iar", line = "\"foo.c\",3  Error[32]: Error message", want = {line = 3, filename = "foo.c"}},
        { rule = "iar", line = "\"foo.c\",3  Warning[32]: Error message", want = {line = 3, filename = "foo.c", type = "warning"}},

        { rule = "ibm", line = "foo.c(2:0) : informational EDC0804: Function foo is not referenced.", want = {col = 0, line = 2, filename = "foo.c"}},
        { rule = "ibm", line = "foo.c(3:8) : warning EDC0833: Implicit return statement encountered.", want = {col = 8, line = 3, filename = "foo.c"}},
        { rule = "ibm", line = "foo.c(5:5) : error EDC0350: Syntax error.", want = { col = 5, line = 5, filename = "foo.c"}},

        { rule = "irix", line = "ccom: Error: foo.c, line 2: syntax error", want = {line = 2, filename = "foo.c"}},
        { rule = "irix", line = "cc: Severe: /src/Python-2.3.3/Modules/_curses_panel.c, line 17: Cannot find file <panel.h> ...", want = {line = 17, filename = "/src/Python-2.3.3/Modules/_curses_panel.c"}},
        { rule = "irix", line = "cc: Info: foo.c, line 27: ...", want = {line = 27, filename = "foo.c", type = "info"}},
        { rule = "irix", line = "cfe: Warning 712: foo.c, line 2: illegal combination of pointer and ...", want = {line = 2, filename = "foo.c", type = "warning"}},
        { rule = "irix", line = "cfe: Warning 600: xfe.c: 170: Not in a conditional directive while ...", want = {line = 170, filename = "xfe.c", type = "warning"}},
        { rule = "irix", line = "/usr/lib/cmplrs/cc/cfe: Error: foo.c: 1: blah blah", want = {line = 1, filename = "foo.c"}},
        { rule = "irix", line = "/usr/lib/cmplrs/cc/cfe: warning: foo.c: 1: blah blah", want = {line = 1, filename = "foo.c", type = "warning"}},
        { rule = "irix", line = "foo bar: baz.f, line 27: ...", want = {line = 27, filename = "baz.f"}},

        { rule = "java",  line = "\tat org.foo.ComponentGateway.doGet(ComponentGateway.java:172)", want = {line = 172, filename = "ComponentGateway.java"}},
        { rule = "java",  line = "\tat javax.servlet.http.HttpServlet.service(HttpServlet.java:740)", want = {line = 740, filename = "HttpServlet.java"}},
        { rule = "java",  line = "==1332==    at 0x4040743C: System::getErrorString() (../src/Lib/System.cpp:217)", want = {line = 217, filename = "../src/Lib/System.cpp"}},
        { rule = "java",  line = "==1332==    by 0x8008621: main (vtest.c:180)", want = {line = 180, filename = "vtest.c", type = "warning"}},

        { rule = "gradle_kotlin", line = "e: file:///src/Test.kt:267:5 foo: bar", want = {col = 5, line = 267, filename = "/src/Test.kt"}},
        { rule = "gradle_kotlin", line = "w: file:///src/Test.kt:267:5 foo: bar", want = {col = 5, line = 267, filename = "/src/Test.kt", type = "warning"}},

        { rule = "jikes_file", line = "Found 2 semantic errors compiling \"../javax/swing/BorderFactory.java\":", want = { filename = "../javax/swing/BorderFactory.java"}},
        { rule = "jikes_file", line = "Issued 1 semantic warning compiling \"java/awt/Toolkit.java\":", want = { filename = "java/awt/Toolkit.java"}},

        { rule = "maven", line = "FooBar.java:[111,53] no interface expected here", want = {col = 53, line = 111, filename = "FooBar.java"}},
        { rule = "maven", line = "[ERROR] /Users/cinsk/hello.java:[651,96] ';' expected", want = {col = 96, line = 651, filename = "/Users/cinsk/hello.java"}},
        { rule = "maven", line = "[WARNING] /foo/bar/Test.java:[27,43] unchecked conversion", want = {col = 43, line = 27, filename = "/foo/bar/Test.java", type = "warning"}},

        { rule = "clang_include", line = "In file included from foo.cpp:2:", want = {line = 2, filename = "foo.cpp", type = "info"}},

        { rule = "gcc_include", line = "In file included from /usr/include/c++/3.3/backward/warn.h:4,", want = {line = 4, filename = "/usr/include/c++/3.3/backward/warn.h"}},
        { rule = "gcc_include", line = "                 from /usr/include/c++/3.3/backward/iostream.h:31:0,", want = {col = 0, line = 31, filename = "/usr/include/c++/3.3/backward/iostream.h"}},
        { rule = "gcc_include", line = "                 from test_clt.cc:1:", want = {line = 1, filename = "test_clt.cc"}},
        { rule = "gcc_include", line = "\tfrom plain-exception.rb:3:in `proxy'", want = {line = 3, filename = "plain-exception.rb"}},
        { rule = "gcc_include", line = "\tfrom plain-exception.rb:12", want = {line = 12, filename = "plain-exception.rb"}},

        { rule = "ruby_Test::Unit", line = "    [examples/test-unit.rb:28:in `here_is_a_deep_assert'", want = {line = 28, filename = "examples/test-unit.rb"}},
        { rule = "ruby_Test::Unit", line = "     examples/test-unit.rb:19:in `test_a_deep_assert']:", want = {line = 19, filename = "examples/test-unit.rb"}},

        { rule = "gmake", line = "make: *** [Makefile:20: all] Error 2", want = {line = 20, filename = "Makefile", type = "info"}},
        { rule = "gmake", line = "make[4]: *** [sub/make.mk:19: all] Error 127", want = {line = 19, filename = "sub/make.mk", type = "info"}},
        { rule = "gmake", line = "gmake[4]: *** [sub/make.mk:19: all] Error 2", want = {line = 19, filename = "sub/make.mk", type = "info"}},
        { rule = "gmake", line = "gmake-4.3[4]: *** [make.mk:1119: all] Error 2", want = {line = 1119, filename = "make.mk", type = "info"}},
        { rule = "gmake", line = "Make-4.3: *** [make.INC:1119: dir/all] Error 2", want = {line = 1119, filename = "make.INC", type = "info"}},

        { rule = "gnu", line =  "foo.adb:61:11:  [...] in call to size declared at foo.ads:11", want = {col = 11, line = 61, filename = "foo.adb"}},
        { rule = "gnu", line =  "foo.c:8: message", want = {line = 8, filename = "foo.c"}},
        { rule = "gnu", line =  "../foo.c:8: W: message", want = {line = 8, filename = "../foo.c", type = "warning"}},
        { rule = "gnu", line =  "/tmp/foo.c:8:warning message", want = {line = 8, filename = "/tmp/foo.c", type = "warning"}},
        { rule = "gnu", line =  "foo/bar.py:8: FutureWarning message", want = {line = 8, filename = "foo/bar.py", type = "warning"}},
        { rule = "gnu", line =  "foo.py:8: RuntimeWarning message", want = {line = 8, filename = "foo.py", type = "warning"}},
        { rule = "gnu", line =  "foo.c:8:I: message", want = {line = 8, filename = "foo.c", type = "info"}},
        { rule = "gnu", line =  "foo.c:8.23: note: message", want = {col = 23, line = 8, filename = "foo.c", type = "info"}},
        { rule = "gnu", line =  "foo.c:8.23: info: message", want = {col = 23, line = 8, filename = "foo.c", type = "info"}},
        { rule = "gnu", line =  "foo.c:8:23:information: message", want = {col = 23, line = 8, filename = "foo.c", type = "info"}},
        { rule = "gnu", line =  "foo.c:8.23-45: Informational: message", want = {col = 23, col_end = 45, line = 8, filename = "foo.c", type = "info"}},
        { rule = "gnu", line =  "foo.c:8-23: message", want = {line = 8, line_end = 23, filename = "foo.c"}},
        { rule = "gnu", line =  "   |foo.c:8: message", want = {line = 8, filename = "foo.c"}},

        -- ;; The next one is not in the GNU standards AFAICS.
        -- ;; Here we seem to interpret it as LINE1-LINE2.COL2.
        { rule = "gnu", line = "foo.c:8-45.3: message", want = {col = 3, line = 8, line_end = 45, filename = "foo.c"}},
        -- deleting this one because it doesn't make sense. what does it even mean?
        -- { rule = "gnu", line = "foo.c:8.23-9.1: message", want = {col = 23 (8 . 9) "foo.c")
        { rule = "gnu", line = "jade:dbcommon.dsl:133:17:E: missing argument for function call", want = {col = 17, line = 133, filename = "dbcommon.dsl"}},
        { rule = "gnu", line = "G:/cygwin/dev/build-myproj.xml:54: Compiler Adapter 'javac' can't be found.", want = {line = 54, filename = "G:/cygwin/dev/build-myproj.xml"}},
        { rule = "gnu", line = "file:G:/cygwin/dev/build-myproj.xml:54: Compiler Adapter 'javac' can't be found.", want = {line = 54, filename = "G:/cygwin/dev/build-myproj.xml"}},
        -- deleting this one because {standard input} isn't a real filename
        -- { rule = "gnu", line = "{standard input}:27041: Warning: end of file not at end of a line; newline inserted", want = {line = 27041, type = "warning"}},
        { rule = "gnu", line = "boost/container/detail/flat_tree.hpp:589:25:   [ skipping 5 instantiation contexts, use -ftemplate-backtrace-limit=0 to disable ]", want = {col = 25, line = 589, filename = "boost/container/detail/flat_tree.hpp", type = "info"}},
        -- not sure why the "gnu" rule is overloaded
        -- ;; ruby (uses gnu)
        { rule = "gnu", line = "plain-exception.rb:7:in `fun': unhandled exception", want = {line = 7, filename = "plain-exception.rb"}},
        { rule = "gnu", line = "examples/test-unit.rb:10:in `test_assert_raise'", want = {line = 10, filename = "examples/test-unit.rb"}},
        -- handle spaces correctly
        { rule = "gnu", line = "memes/what are you referring to as gnu is in fact:17:gnu.", want = {line = 17, filename = "memes/what are you referring to as gnu is in fact"}},
        -- does not match timestamps
        { rule = "gnu", line = "Task finished at Wed Nov 6 20:00:02", want = nil},

        { rule = "cucumber", line = "Scenario: undefined step  # features/cucumber.feature:3", want = {line = 3, filename = "features/cucumber.feature"}},
        { rule = "cucumber", line = "      /home/gusev/.rvm/foo/bar.rb:500:in `_wrap_assertion'", want = {line = 500, filename = "/home/gusev/.rvm/foo/bar.rb"}},

        { rule = "lcc", line = "E, file.cc(35,52) Illegal operation on pointers", want = {col = 52, line = 35, filename = "file.cc"}},
        { rule = "lcc", line = "W, file.cc(36,52) blah blah", want = {col = 52, line = 36, filename = "file.cc", type = "warning"}},

        { rule = "makepp", line = "makepp: Scanning `/foo/bar.c'", want = {filename = "/foo/bar.c"}},
        { rule = "makepp", line = "makepp: warning: bla bla `/foo/bar.c' and `/foo/bar.h'", want = {filename = "/foo/bar.c", type = "warning"}},
        { rule = "makepp", line = "makepp: bla bla `/foo/Makeppfile:12' bla", want = {line = 12, filename = "/foo/Makeppfile"}},
        -- we could match either filenames
        { rule = "makepp", line = "makepp: bla bla `/foo/bar.c' and `/foo/bar.h'", want = {filename = "/foo/bar.c"}},

        { rule = "mips_1", line = "TrimMask (255) in solomon.c may be indistinguishable from TrimMasks (93) in solomo.c due to truncation", want = {line = 255, filename = "solomon.c"}},

        { rule = "mips_2", line = "name defined but never used: LinInt in cmap_calc.c(199)", want = {line = 199, filename = "cmap_calc.c"}},

        { rule = "oracle", line = "Semantic error at line 528, column 5, file erosacqdb.pc:", want = {col = 5, line = 528, filename = "erosacqdb.pc"}},
        { rule = "oracle", line = "Error at line 41, column 10 in file /usr/src/sb/ODBI_BHP.hpp", want = {col = 10, line = 41, filename = "/usr/src/sb/ODBI_BHP.hpp"}},
        { rule = "oracle", line = "PCC-02150: error at line 49, column 27 in file /usr/src/sb/ODBI_dxfgh.pc", want = {col = 27, line = 49, filename = "/usr/src/sb/ODBI_dxfgh.pc"}},
        { rule = "oracle", line = "PCC-00003: invalid SQL Identifier at column name in line 12 of file /usr/src/sb/ODBI_BHP.hpp", want = {line = 12, filename = "/usr/src/sb/ODBI_BHP.hpp"}},
        { rule = "oracle", line = "PCC-00004: mismatched IF/ELSE/ENDIF block at line 27 in file /usr/src/sb/ODBI_BHP.hpp", want = {line = 27, filename = "/usr/src/sb/ODBI_BHP.hpp"}},
        { rule = "oracle", line = "PCC-02151: line 21 column 40 file /usr/src/sb/ODBI_BHP.hpp:", want = {col = 40, line = 21, filename = "/usr/src/sb/ODBI_BHP.hpp"}},

        { rule = "perl", line = "syntax error at automake line 922, near \"':'\"", want = {line = 922, filename = "automake"}},
        { rule = "perl", line = "Died at test.pl line 27.", want = {line = 27, filename = "test.pl"}},
        { rule = "perl", line = "store::odrecall('File_A', 'x2') called at store.pm line 90", want = {line = 90, filename = "store.pm"}},
        { rule = "perl", line = "\t(in cleanup) something bad at foo.pl line 3 during global destruction.", want = {line = 3, filename = "foo.pl"}},
        { rule = "perl", line = "GLib-GObject-WARNING **: /build/buildd/glib2.0-2.14.5/gobject/gsignal.c:1741: instance `0x8206790' has no handler with id `1234' at t-compilation-perl-gtk.pl line 3.", want = {line = 3, filename = "t-compilation-perl-gtk.pl"}},

        { rule = "php", line = "Parse error: parse error, unexpected $ in main.php on line 59", want = {line = 59, filename = "main.php"}},
        { rule = "php", line = "Fatal error: Call to undefined function: mysql_pconnect() in db.inc on line 66", want = {line = 66, filename = "db.inc"}},

        { rule = "rxp", line = "in unnamed entity at line 71 char 8 of file:///home/reto/test/group.xml", want = {col = 8, line = 71, filename = "/home/reto/test/group.xml"}},
        { rule = "rxp", line = "in unnamed entity at line 4 char 8 of file:///home/reto/test/group.xml", want = {col = 8, line = 4, filename = "/home/reto/test/group.xml"}},

        { rule = "shellcheck", line = "In autogen.sh line 48:", want = {line = 48, filename = "autogen.sh"}},

        { rule = "sun", line = "cc-1020 CC: REMARK File = CUI_App.h, Line = 735", want = {line = 735, filename = "CUI_App.h", type = "info"}},
        { rule = "sun", line = "cc-1070 cc: WARNING File = linkl.c, Line = 38", want = {line = 38, filename = "linkl.c", type = "warning"}},
        { rule = "sun", line = "cf90-113 f90comp: ERROR NSE, File = Hoved.f90, Line = 16, Column = 3", want = {col = 3, line = 16, filename = "Hoved.f90"}},

        { rule = "sun_ada", line = "/home3/xdhar/rcds_rc/main.a, line 361, char 6:syntax error: \",\" inserted", want = {col = 6, line = 361, filename = "/home3/xdhar/rcds_rc/main.a"}},

        { rule = "watcom", line = "..\\src\\ctrl\\lister.c(109): Error! E1009: Expecting ';' but found '{'", want = {line = 109, filename = "..\\src\\ctrl\\lister.c"}},
        { rule = "watcom", line = "..\\src\\ctrl\\lister.c(120): Warning! W201: Unreachable code", want = {line = 120, filename = "..\\src\\ctrl\\lister.c", type = "warning"}},

    }

    busted.it("captures error information", function()
        for i, v in ipairs(cases) do
            local got = rules[v.rule]:match(v.line)

            -- discard spans; we don't care about that in tests
            if got ~= nil then
                got = vim.tbl_map(function(cap)
                    return cap.value
                end, got)
            end

            assert(
                tbl_equal(got, v.want),
                string.format("Test #%d failed for rule '%s' with line '%s'\n\tgot %s, want %s", i, v.rule, v.line, vim.inspect(got), vim.inspect(v.want))
            )
        end
    end)
end)

