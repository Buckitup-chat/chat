%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: ["credo_checks/**/*.ex"],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          #
          ## Consistency Checks
          #
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},

          #
          ## Design Checks
          #
          {Credo.Check.Design.AliasUsage,
           [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 0]},
          {Credo.Check.Design.TagTODO, [exit_status: 0]},
          {Credo.Check.Design.TagFIXME, []},

          #
          ## Readability Checks
          #
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {Credo.Check.Readability.WithSingleClause, []},

          ## Readability — newly enabled (exit_status: 0 until codebase is clean)
          {Credo.Check.Readability.NestedFunctionCalls, [min_pipeline_length: 3, exit_status: 0]},
          {Credo.Check.Readability.PreferUnquotedAtoms, [exit_status: 0]},
          # alias may precede use when the use references it (see credo_checks/)
          {Chat.Credo.Check.StrictModuleLayout, [exit_status: 0]},

          #
          ## Refactoring Opportunities
          #
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 20]},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.WithClauses, []},

          ## Refactoring — newly enabled (exit_status: 0 until codebase is clean)
          {Credo.Check.Refactor.AppendSingleItem, [exit_status: 0]},
          {Credo.Check.Refactor.CaseTrivialMatches, [exit_status: 0]},
          {Credo.Check.Refactor.FilterCount, [exit_status: 0]},
          {Credo.Check.Refactor.PerceivedComplexity, [exit_status: 0]},
          {Credo.Check.Refactor.UtcNowTruncate, [exit_status: 0]},

          #
          ## Warnings
          #
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFileExtension, []},

          ## Warnings — newly enabled (exit_status: 0 until codebase is clean)
          {Credo.Check.Warning.Dbg, [exit_status: 0]},
          {Credo.Check.Warning.UnusedMapOperation, [exit_status: 0]},
          {Credo.Check.Warning.UnsafeToAtom, [exit_status: 0]},

          #
          ## credo_naming — module/filename consistency (exit_status: 0 until clean)
          #
          {CredoNaming.Check.Consistency.ModuleFilename,
           [
             exit_status: 0,
             excluded_paths: ["test/support", "priv", "rel", "mix.exs"],
             plugins: [CredoNaming.Check.Consistency.ModuleFilename.Plugins.Phoenix],
             acronyms: [
               {"GraphQL", "graphql"},
               {"PubSub", "pub_sub"},
               {"GenServer", "gen_server"},
               {"OAuth", "oauth"},
               {"OpenAI", "open_ai"},
               {"AssemblyAI", "assembly_ai"},
               {"LLM", "llm"},
               {"E2E", "e2e"}
             ]
           ]},
          {CredoNaming.Check.Warning.AvoidSpecificTermsInModuleNames,
           [exit_status: 0, terms: ["Manager", ~r/Helpers?/, "Utils"]]},

          #
          ## credo_unnecessary_reduce (exit_status: 0 until clean)
          #
          {CredoUnnecessaryReduce.Check, [exit_status: 0]},

          #
          ## oeditus_credo — idiomatic refactoring (exit_status: 0 until clean)
          #
          {OeditusCredo.Check.Readability.UnnecessaryInterpolatingSigil, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferCasePatternMatching, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferMultiHeadFunction, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferMultiHeadForNil, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferTaggedTuplesForErrors, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferWithClause, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferDestructuring, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferPipelineOperator, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferFunctionCapture, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferDotAccessForStructs, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferInplaceMapMatching, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferInplaceListMatching, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferInplaceBinaryMatching, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferShortFieldAccessCapture, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferPatternMatchingForEmptiness, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferStringBoundariesOverRegex, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferMapMerge, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.PreferForComprehensionOverFilterMap, [exit_status: 0]},
          {OeditusCredo.Check.Refactoring.AvoidUnawaitedTaskAsync, [exit_status: 0]},

          #
          ## oeditus_credo — warnings (exit_status: 0 until clean)
          #
          {OeditusCredo.Check.Warning.SwallowingException, [exit_status: 0]},
          {OeditusCredo.Check.Warning.CallbackHell, [exit_status: 0]},
          {OeditusCredo.Check.Warning.SyncOverAsync, [exit_status: 0]},
          {OeditusCredo.Check.Warning.MissingHandleAsync, [exit_status: 0]},
          {OeditusCredo.Check.Warning.SilentErrorCase, [exit_status: 0]},
          {OeditusCredo.Check.Warning.DirectStructUpdate, [exit_status: 0]},
          {OeditusCredo.Check.Warning.InefficientFilter, [exit_status: 0]},
          {OeditusCredo.Check.Warning.NPlusOneQuery, [exit_status: 0]},
          {OeditusCredo.Check.Warning.MissingPreload, [exit_status: 0]},
          {OeditusCredo.Check.Warning.UnmanagedTask, [exit_status: 0]},
          {OeditusCredo.Check.Warning.BlockingInPlug, [exit_status: 0]},
          {OeditusCredo.Check.Warning.TelemetryInRecursiveFunction, [exit_status: 0]},

          #
          ## oeditus_credo — security (exit_status: 0 until reviewed)
          #
          {OeditusCredo.Check.Security.SQLInjection, [exit_status: 0]},
          {OeditusCredo.Check.Security.OSCommandInjection, [exit_status: 0]},
          {OeditusCredo.Check.Security.CodeInjection, [exit_status: 0]},
          {OeditusCredo.Check.Security.XSSVulnerability, [exit_status: 0]},
          {OeditusCredo.Check.Security.HardcodedCredentials, [exit_status: 0]},
          {OeditusCredo.Check.Security.UnsafeDeserialization, [exit_status: 0]},
          {OeditusCredo.Check.Security.PathTraversal, [exit_status: 0]},
          {OeditusCredo.Check.Security.InsecureDirectObjectReference, [exit_status: 0]},
          {OeditusCredo.Check.Security.SensitiveDataExposure, [exit_status: 0]},
          {OeditusCredo.Check.Security.TOCTOU, [exit_status: 0]},
          {OeditusCredo.Check.Security.SSRFVulnerability, [exit_status: 0]},
          {OeditusCredo.Check.Security.UnrestrictedFileUpload, [exit_status: 0]},
          {OeditusCredo.Check.Security.IncorrectAuthorization, [exit_status: 0]},
          {OeditusCredo.Check.Security.ImproperInputValidation, [exit_status: 0]}
        ],
        disabled: [
          #
          ## Built-in — intentionally off
          #
          {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
          {Credo.Check.Consistency.UnusedVariableNames, []},
          {Credo.Check.Design.DuplicatedCode, []},
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Credo.Check.Readability.AliasAs, []},
          {Credo.Check.Readability.BlockPipe, []},
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.SeparateAliasRequire, []},
          {Credo.Check.Readability.SingleFunctionToBlockPipe, []},
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.FilterReject, []},
          {Credo.Check.Refactor.IoPuts, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.RejectFilter, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LazyLogging, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MixEnv, []},

          #
          ## oeditus_credo — off (overlap, opt-in, or too broad)
          #
          {OeditusCredo.Check.Refactoring.AvoidSinglePipe, false},
          {OeditusCredo.Check.Refactoring.PreferListPrepend, false},
          {OeditusCredo.Check.Refactoring.ChangeRiskAntiPatterns, false},
          {OeditusCredo.Check.Refactoring.SuggestFSM, false},
          {OeditusCredo.Check.Warning.UnsafeMapAccess, false},
          {OeditusCredo.Check.Warning.MissingThrottle, false},
          {OeditusCredo.Check.Warning.InlineJavascript, false},
          {OeditusCredo.Check.Warning.MissingTelemetryInAuthPlug, false},
          {OeditusCredo.Check.Warning.MissingTelemetryForExternalHttp, false},
          {OeditusCredo.Check.Warning.MissingErrorHandling, false},
          {OeditusCredo.Check.Security.MissingAuthentication, false},
          {OeditusCredo.Check.Security.MissingAuthorization, false},
          {OeditusCredo.Check.Security.MissingCSRFProtection, false}
        ]
      }
    }
  ]
}
