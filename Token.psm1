# this file contains:
# - Class definitin for Token objects
# - Enum for TokenType
# - dictionary for reserved words

enum TokenType {
    
    #single character punctuation & operators
    COMMA; DOT; SEMI; STAR; MINUS; PLUS; SLASH; LPAREN;  RPAREN;  
    #comparisons  
    BANG; BANG_EQUAL; EQUAL; EQUAL_EQUAL; 
    GREATER; GREATER_EQUAL; LESS; LESS_EQUAL;
    #literals
    STRING; NUMBER; IDENTIFIER; 
    #keywords 
    SELECT; INTO; FROM; WHERE; GROUP_BY; ORDER_BY 
    WITH; UNION; PARTITION; OVER; AS; 

    EOF
}
class Token {
    [TokenType] $type;
    [String] $lexeme;
    [String] $literal   #not sure if we have object type to use for generic field.
                        #So numeric literals will be stored as strings.
                        #as are not evaluating, this should be OK
    [int] $pos  # character position in input file 

    #constructor
    Token([TokenType] $token, [String] $lexeme, [String] $literal, [int] $pos) {
        $this.type = $token
        $this.lexeme = $lexeme;
        $this.literal = $literal;
        $this.pos = $pos;
    }
    # pretty printer
    [String] pp() {
        $rts = $this.type.toString() + ":" + $this.lexeme + ":" + $this.literal + ":" + $this.pos.tostring();
        return $rts
    }
}