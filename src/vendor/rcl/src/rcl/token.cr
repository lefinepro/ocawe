# RCL Token

module RCL
  # Token types for RCL lexer
  enum TokenType
    Identifier
    String
    Number
    Equal
    Comma
    Dot
    Do
    End
    LBracket
    RBracket
    EOF
  end

  # Token record
  record Token,
    type : TokenType,
    value : String,
    line : Int32,
    column : Int32
end
