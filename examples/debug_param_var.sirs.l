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
              "name": "rate",
              "type": "f64",
              "value": {"literal": 2.0}
            }
          },
          {
            "let": {
              "name": "sample_value",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "poisson",
                  "params": [{"var": "rate"}]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "sample_value"}]
              }
            }
          }
        ]
      }
    }
  }
}