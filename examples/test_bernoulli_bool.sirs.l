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
              "name": "coin_flip",
              "type": "bool",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"literal": 0.5}]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "print_bool",
                "args": [{"var": "coin_flip"}]
              }
            }
          }
        ]
      },
      "print_bool": {
        "args": [{"name": "value", "type": "bool"}],
        "return": "void",
        "body": [
          {
            "expression": {
              "call": {
                "function": "std_print_int",
                "args": [{"literal": 42}]
              }
            }
          }
        ]
      }
    }
  }
}