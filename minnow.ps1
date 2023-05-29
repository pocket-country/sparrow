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
# helpers that work on input buffer
function IsAtEnd() {
    return ($current -eq $textLength)
}
function Peek($n){ # look ahead n characters
    $tc = $src[$current + $n];
    return $tc;
}
function Write($n){
    #get current character, make an extended chr object.  line and current position are globals
    for ($i = 0; $i -lt $n; $i++) {
        $tc = $src[$current + $i];
        $eChr = []::new($tc, $line, $current);
        $eChrs.add($eChr);
    }
    return ($current + $n);
}
function WriteBlank(){
    #for use in  whitespace processing, write a space
    $eChr = []::new(" ", $line, $current);
    $eChrs.add($eChr);
    return ($current++);
}
function Skip($n) { # skip ahead n characters
    return ($current + $n);
}

# logging 
function LogAction( $action) {
    if ($doggit) {add-content $mlog " Action Called: $action"}
}
function LogState() {
    if ($doggit) {add-content $mlog "In state ($state) looking at ($c)[($current + $n)]"}
}
# comment "stack" is just a number for now.  Later, maybe store actual text in an actual stack.
function PushComment($cs) {
    return ($cs++);
}
function PopComment($cs) {
    return ($cs--);
}
# global variables count comments and lines in input
function BumpLine($lc) {
    return (lc++);
}
function BumpComment($cc) {
    return (cc++);
}

#set up log for testing state dynamics
$doggit = $true;
if ($doggit) {
    $mlog = "MinnowLog.txt";
    $null = new-item $mlog -force ;
}

# int main(int argc, char *argv[]) { }
if ($args) {$script_name = $args} else {$script_name = "./testMinnow.sql"}
$src = Get-Content $script_name -raw;

# global tracking  variables.
$current = 0;               #current character position in input text
$textLength = $src.Length;  #reference for EOF detection
$lines = 0;                 #text lines in input (count newlines)
$comments = 0;              #comments found (nested count as one)

# the state machine loop:
# everyone just numbers these, but then ... which is which? 
# I'm gonna use a 3 chr mnemonic
$state = "beg";

# for setting up a 'safety' during debugging
$iter = 0;

# first pass write everything out for clarity.  Then refactor into functions for efficiency.

while (-not (IsAtEnd)) {

    $iter++; 
    if ($iter -ge 100) {Write-Host "Hit The Wall!"; Exit}
    
    Switch ($state) {
        'beg' { #1 'home' or beginning
            $c = Peek(1);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds1'; break;}
                # not wired up at the moment '/'  {$state = 'bc1'; break;}
                ' '  {$state = 'ws1'; 
                        LogAction("write a blank"); 
                        WriteBlank;
                        break;}
                '\t' {$state = 'ws1'; 
                        LogAction("write a blank");
                        WriteBlank;
                        break;}
                '\n' {$state = 'ws1'; 
                        LogAction("bump line count + write a blank"); 
                        BumpLine;
                        WriteBlank;
                        break;}
                default { $state = 'beg'; 
                        LogAction("process a regular charcter"); 
                        Write(1);
                        break;}
            }
            break;
        }
        'ds1' { #2 saw first dash of a double dash, look for second 
            $c = Peek(2);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds2'; 
                        Skip(2);        # saw two dashes, jump  over 'em both
                        $comments = PushComment; # and we are in a comment, boys
                        break;}
                default {$state = 'beg'; 
                        Write(2); #false alarm.  Write this character, and the prior dash which as it turns out did not signify  a comment.
                        break;}
            }
            break;
        }
        'ds2' { #3 saw second dash of a double dash comment - so in a comment.  Chew it up till newline.
            $c = Peek(1);
            LogState;
            switch ($c) {
                '\n'  {$state = 'beg'; 
                    LogAction("end double dash comment, inc. line and comment count"); 
                    Skip(1);
                    PopComment;
                    BumpComment;
                    BumpLine;
                    break;}
                default {$state = 'ds2'; 
                    LogAction("process character inside double dash comment"); 
                    Skip(1);
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
                ' '  {$state = 'ws1'; Skip(1); break;}
                '\t' {$state = 'ws1'; Skip(1); break;}
                '\n' {$state = 'ws1'; Skip(1); BumpLine; break;}
                default {$state = 'beg'; 
                    LogAction("leaving white space, process regular character"); 
                    Write(1);
                    break}
            }
            break;
        }
    } # end state switch
} # end main while loop
#if state = final then OK else error
#any post processing

# ###