{
  "program": {
    "entry": "main",
    "functions": {
      "main": {
        "args": [],
        "return": "void",
        "body": [
          {
            "let": {
              "name": "x",
              "type": "f64",
              "value": {"literal": 1.0}
            }
          },
          {
            "let": {
              "name": "y",
              "type": "f64",
              "value": {"literal": 2.0}
            }
          },
          {
            "let": {
              "name": "sum",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {"var": "x"},
                    {"var": "y"}
                  ]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "sum"}]
              }
            }
          }
        ]
      }
    }
  }
}