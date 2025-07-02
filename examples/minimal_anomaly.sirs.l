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
              "name": "anomaly_score",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "poisson",
                  "params": [{"literal": 2.0}]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "print_float",
                "args": [{"var": "anomaly_score"}]
              }
            }
          }
        ]
      },
      "print_float": {
        "args": [{"name": "value", "type": "f64"}],
        "return": "void",
        "body": [
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "value"}]
              }
            }
          }
        ]
      }
    }
  }
}