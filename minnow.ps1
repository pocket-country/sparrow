# Minnow is a pre-processor for T-SQL code.
# Wanted to:
# - be able to handle nested block comments (PITA, see tail.ps1)
# - create a 'minified' sql file w/ dup whitespace removed, all ws -> blank, comments removed
# - create an input file for sparrow so I don't have to embed all of the above into my scanner
#
# Note  that the third item above will require creating a data format to pass along position info
# for the scanner along with txt so can report errors  correctly.  Here we are trading the reduction of
# complexity in terms of not having the scanner deal with comment parsing for increased complexity
# of tracking position for error messages.
#
# Also, always wanted to build a DFA/state machine for fun.  Old Skool Cook.  #
# Choose to build the state transition table "in code" vs
# more general purpose  method (see a useful set of blog posts at //)
# Can I bang this out in an afternoon?  Have a lot of the thinking/design done ...

# We are in a scripting language have to declare functions before use!  Just like the olden days.

# class - in the Pascal sense, a data record, to hold an 'extended character - our IR that holds position info as well as character
class EC {
    [char] $byte;
    [int] $atline;
    [int] $atoffset;
    #constructor
    EC([char] $c, [int] $l, [int] $o) {
        $this.byte = $c;
        $this.atline = $l;
        $this.atoffset = $o;
    }
}
# holds internal representation we are building, an array of extended character objects.
$eChars = New-Object -TypeName "System.Collections.ArrayList";

# class to encapsulate the input text file/string/buffer ... like an actual class with methods.
# I wanted to write a scrappy little script without this stuff, but ...
# Wasted a full day of my life trying to find a weird bug.  Return from write, value in 
# global $Current reverts to 0 on first iteration works fine on subsequent iterations.
# Got lost in PS's weired scripty scope rules, returns, lack of type declarations at 'script' level
# So am hoping more modern encapsulation/data structure will fix the problem.  Still no idea what bug is
# Am gonna pretend I'm writing Java/C++/C#

# helpers that work on input buffer
function IsAtEnd() { #boolean - this seems to work despite crazy semantics and implicit converesion of poweershell return statement
    return ($current -eq ($src.length))
}
function Peek($n) { # look at current (or subsequent) charater in input buffeer
    $tc = $src[$current + $n];
    if ($doggit) {add-content $mlog " Peeking at $current + $n : $tc"}
    return $tc;
}
# these three functions update current pointer (note return tranforms into an object! UGG that several hours of my life i'll never get back.)
# i.e. "consume" characters.
function Write($n){ #  eat current character(s), make an extended chr object.
    Write-Host "In Write";
    for ($i = 0; $i -lt $n; $i++) {
        $tc = $src[$current + $i];
        $to = $current - $linePos;
        $eChar = [EC]::new($tc, $lineNum, $to);
        $eChars.add($eChar);
    }
    #Write-Host $current;
    #Write-Host $n;
    $script:current = $current + $n;
    Write-Host $script:current;
}
function WriteBlank(){ #for use in  whitespace processing, write a space
    $to = $current - $linePos;
    $eChar = [EC]::new(" ", $lineNum, $to);
    $eChars.add($eChar);
    $script:current = $current + 1;
}
function Skip($n) { # skip ahead n characters
    $script:current = $current + $n;
}

# logging
function LogAction( $action) {
    if ($doggit) {add-content $mlog " Action Called: $action"}
}
function LogState() {
    if ($doggit) {add-content $mlog "In state $state looking at [$current]:$c"}
}
# comment "stack" is just a number for now.  Later, maybe store actual text in an actual stack.
function PushComment() {
    $script:commentStack++;
}
function PopComment() {
    $script:commentStack--;
}
# global variables count comments and lines in input
function NewLine() { # process a new line.
    # call after writing blank for or skipping newline.  This implicit coupling makes me uneasy.
    $script:lineNum++;    # bump line counter;
    $script:linePos = $current; # capture starting position of now current line;
                                # which starts following the newline we just wrote/skipped
    #this is where we would updatee counts of blank lines, lines containing a comment, etc.
}

#set up log for testing state dynamics
$doggit = $true;
if ($doggit) {
    $mlog = "MinnowLog.txt";
    $null = new-item $mlog -force ;
}

# global tracking  variables.
$current = 0;               #current character position in input text
$lineNum = 1;               #current line in input text
$linePos = 0;               #position in text of first character of current line

$commentStack = 0;          #actually a counter, how deep are we in nested comments.

# statistics - counts of comments, blank lines, code lines, etc

#initialize state loop
$state = "beg";     # everyone just numbers these, but then ... which is which?
                    # I'm gonna use a 3 chr mnemonic
$iter = 0; # for setting up a 'safety' during debugging

# read in SQL text and start processing here ... int main(int argc, char *argv[]) { }
if ($args) {$script_name = $args} else {$script_name = "./testMinnow.sql"}
$src = Get-Content $script_name -raw;

# first pass write everything out for clarity.  Then refactor into functions for efficiency.

# the state machine loop:
while (-not (IsAtEnd)) {
    $iter++;
    if ($iter -ge 4) {Write-Host "Hit The Wall!"; Break;} else {Write-Host "Iteration ($iter)"}

    Switch ($state) {
        'beg' { #1 'home' or beginning
            $c = Peek(0);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds1'; break;}
                # not wired up at the moment '/'  {$state = 'bc1'; break;}
                ' '  {$state = 'ws1';
                        LogAction("write a blank");
                        $current = WriteBlank;
                        break;}
                '\t' {$state = 'ws1';
                        LogAction("write a blank");
                        $current = WriteBlank;
                        break;}
                '\n' {$state = 'ws1';
                        LogAction("write a blank for newline & process newline");
                        # order is important.  These two calls are coupled functionally
                        $current = WriteBlank;
                        NewLine;
                        break;}
                default { $state = 'beg';
                        LogAction("process a regular charcter");
                        Write-Host "before write"
                        Write-Host $current;
                        $current = Write(1);
                        Write-Host "After write"
                        Write-Host $current;
                        break;}
            }
            break;
        }
        'ds1' { #2 saw first dash of a double dash, look for second
            $c = Peek(2);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds2';
                        $current = Skip(2);  # second of two dashes, jump  over 'em both
                        PushComment;         # and we are in a comment, boys
                        break;}
                default {$state = 'beg';
                        $current = Write(2); #false alarm.  Write this character, and the prior dash which as it turns out did not signify  a comment.
                        break;}
            }
            break;
        }
        'ds2' { #3 here if saw second dash of a double dash comment - so in a comment.  Chew it up till newline.
            $c = Peek(1);
            LogState;
            switch ($c) {
                '\n'  {$state = 'beg';
                    LogAction("end double dash comment, inc. line and comment count");
                    $current = Skip(1);
                    NewLine;
                    PopComment;
                    break;}
                default {$state = 'ds2';
                    LogAction("skip over character inside double dash comment");
                    $current = Skip(1);
                    break;}
            }
            break;
        }
        'bc1' { #4
            $c = Peek(1);
            LogState;
            switch ($c){
                '*'  {$state = 'bcc'; LogAction("start block commeent"); break}
                default {$state = 'beg'; LogAction("process a regular charcter")}
            }
            break;
        }
        'bcc' { #5
            $c = Peek(1);
            LogState;
            break;
        }
        'bcq' { #6
            $c = Peek(1);
            LogState;
            break;
        }
        'bce' { #7
            $c = Peek(1);
            LogState;
            break;
        }
        'ws1' { # 8: keep skipping consecutive white space
            $c = Peek(1);
            LogState;
            switch ($c) {
                ' '  {$state = 'ws1'; $current = Skip(1); break;}
                '\t' {$state = 'ws1'; $current = Skip(1); break;}
                '\n' {$state = 'ws1'; $current = Skip(1); NewLine; break;}
                default {$state = 'beg';
                    LogAction("leaving white space, process regular character");
                    $current = Write(1);
                    break}
            }
            break;
        }
    } # end state switch
} # end main while loop

#if state = final then OK else error

#any post processing
Write-Host "post processng"
$eChars;
ConvertTo-Json -EnumsAsStrings -depth 10 -InputObject ($eChars) | Out-File "./test.json"

# ###
