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
              "name": "prob",
              "type": "f64",
              "value": {"literal": 0.5}
            }
          },
          {
            "let": {
              "name": "coin_flip",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "prob"}]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "coin_flip"}]
              }
            }
          }
        ]
      }
    }
  }
}