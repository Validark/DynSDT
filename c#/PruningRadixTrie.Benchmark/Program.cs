using System;
using System.IO;
using System.Diagnostics;
using System.IO.Compression;
using System.Collections.Generic;

namespace PruningRadixTrie.Benchmark
{
	static class ExtensionsClass
    {
        private static Random rng = new Random();

        public static void Shuffle<T>(this IList<T> list)
        {
            int n = list.Count;
            while (n > 1)
            {
                int k = rng.Next(n);
                n -= 1;
                T value = list[k];
                list[k] = list[n];
                list[n] = value;
            }
        }
    }

	class Program
	{
		public static List<(string, int)> ReadQueries(string path, int numberOfLinesToRead = int.MaxValue)
		{
			var allTerms = new List<(string term, int score)>();
			if (numberOfLinesToRead == 0) return allTerms;
			var sw = Stopwatch.StartNew();
			try
			{
				using (System.IO.Stream corpusStream = System.IO.File.OpenRead(path))
				{
					using (System.IO.StreamReader sr = new System.IO.StreamReader(corpusStream, System.Text.Encoding.UTF8, false))
					{
						do
						{
							string line = sr.ReadLine();
							if (line == null) break;

							var numberStart = 1 + line.IndexOf('\t');
							var term = line.Substring(0, numberStart - 1);
							var dataStart = line.IndexOf('\t', numberStart + 1);
							var score = line.Substring(numberStart, (dataStart < 0 ? line.Length : dataStart) - numberStart);
							var termData = dataStart < 0 ? null : line.Substring(dataStart + 1);
							allTerms.Add((term, int.Parse(score)));
						} while (--numberOfLinesToRead != 0);
					}
				}
			}
			catch (Exception e)
			{
				Console.WriteLine("Loading terms exception: " + e.Message);
			}

			sw.Stop();
			var powerOf1000 = 0;
			for (long freq = Stopwatch.Frequency, resolution = 1000; freq > resolution; powerOf1000++)
				resolution *= 1000;

			var tickFormatter = "0" + new string(',', powerOf1000) + ".##";
			Console.WriteLine("Parsed " + path + " in " + sw.ElapsedTicks.ToString(tickFormatter) + " ms. (" + allTerms.Count.ToString("N0") + " terms)");
			return allTerms;
		}

		public static void Benchmark()
		{
			if (!File.Exists("terms.txt")) ZipFile.ExtractToDirectory("terms.zip", ".");
			var pruningRadixTrie = new PruningRadixTrie();
			var numAllocatedBytes = GC.GetTotalMemory(true);
			pruningRadixTrie.ReadTermsFromFile("terms.txt");
			var numAllocatedBytes2 = GC.GetTotalMemory(true);
			Console.WriteLine("\tStructure is ~" + (numAllocatedBytes2 - numAllocatedBytes).ToString("0,,.##") + "MB.");
			pruningRadixTrie.WriteTermsToFile("terms.txt");
			Console.WriteLine("Benchmark started ...");
			int termCount = 10;
			{
				int rounds = 1000; // must be some 3rd power of 10, i.e. 1, 1000, 1000000, etc
				string queryString = "microsoft";

				string[] prefixes = new string[queryString.Length + 1];
				for (var i = 0; i <= queryString.Length; i++) // get all prefixes of queryString
					prefixes[i] = queryString.Substring(0, i);

				for (int loop = 0; loop < 100000; loop++) // warm up
					foreach (var prefix in prefixes)
						pruningRadixTrie.GetTopkTermsForPrefix(prefix, termCount);

				var powerOf1000 = 0;
				for (long freq = Stopwatch.Frequency, resolution = 1000000 / rounds; freq > resolution; powerOf1000++)
					resolution *= 1000;
				var tickFormatter = "0" + new string(',', powerOf1000) + ".000000";
				Stopwatch sw = new Stopwatch();
				foreach (var prefix in prefixes)
				{
					// List<(string term, long score)> results = null;
					sw.Restart();
					for (int loop = 0; loop < rounds; loop++)
						/* results = */pruningRadixTrie.GetTopkTermsForPrefix(prefix, termCount);
					sw.Stop();
					Console.WriteLine("queried \"" + prefix + '"' + new string(' ', queryString.Length - prefix.Length + 1) + "in " + sw.ElapsedTicks.ToString(tickFormatter) + " µs");
					// if (results != null)
					// 	Console.WriteLine("[\n"+String.Join(",\n", results.ConvertAll(x => "\t" + x.term + " " + x.score)) + "\n] " + results.Count);
				}
			}

			GC.GetTotalMemory(true);

			{
				if (!File.Exists("queries.txt")) ZipFile.ExtractToDirectory("queries.zip", ".");
				var queries = ReadQueries("queries.txt");
				var queriesCount = queries.Count;
				var TICKS_PER_SECOND = Stopwatch.Frequency;
				Stopwatch counter = Stopwatch.StartNew();
  				var count = 0;
				for (var index = 0; counter.ElapsedTicks < TICKS_PER_SECOND; )
				{
					var myTerm = queries[index];
					++count;
					pruningRadixTrie.GetTopkTermsForPrefix(myTerm.Item1, termCount);
					index = index + 1;
					if (index == queriesCount) index = 0;
				}
				counter.Stop();
				Console.WriteLine(count.ToString("N0") + " random queries were performed in one second.");
			}
		}

		public static void Test2()
		{
			var sw = new Stopwatch();
			var numAllocatedBytes = GC.GetTotalMemory(true);
			if (!File.Exists("terms.txt")) ZipFile.ExtractToDirectory("terms.zip", ".");
			var terms = ReadQueries("terms.txt");
			sw.Start();
			// var dict = new Dictionary<String, NodeTest>();


			sw.Stop();
			var numAllocatedBytes2 = GC.GetTotalMemory(true);
			Console.WriteLine("\tStructure is ~" + (numAllocatedBytes2 - numAllocatedBytes).ToString("0,,.##") + "MB.");
			Console.WriteLine("\tBuilt in " + sw.ElapsedTicks.ToString("0,,,.00") + " seconds");
			Console.WriteLine("Done!");
		}

		public static void Test()
		{
			if (!File.Exists("terms.txt")) ZipFile.ExtractToDirectory("terms.zip", ".");
			var numAllocatedBytes = GC.GetTotalMemory(true);
			PruningRadixTrie trie = new PruningRadixTrie();
			trie.ReadTermsFromFile("terms.txt");
			var numAllocatedBytes2 = GC.GetTotalMemory(true);
			Console.WriteLine("\tStructure is ~" + (numAllocatedBytes2 - numAllocatedBytes).ToString("0,,.##") + "MB.");

			var setters = new List<(String term, long score)>() {
				("tennis championships 2020", 50),
				("tennis academy", 9001), // test cases from the paper
				("tennis championships", 63),

				("tennis championships", 1210), // reset, but this time tennis championships 2020 will be higher
				("tennis championships 2020", 68),
				("tennis championships", 63),
			};

			foreach (var (term, score) in setters)
			{
				trie.Set(term, score, out var myPeers, out var myIndex);
				if (myPeers != null)
					trie.verifySubtree(myPeers, myIndex);
			}

			var terms = trie.GetAllTermsUnsorted();
			var termCount = terms.Count;
			var rand = new Random();

			//*
			var maxTermLength = 0;

			foreach (var (term, _) in terms)
			{
				maxTermLength = Math.Max(maxTermLength, term.Length);
			}
			Console.WriteLine("Fuzzing time!");
			for (var i = 0; ; i++)
			{ // Fuzz forever, until we stop the program, the longest I ran this was 11166182 iterations
				var term = terms[rand.Next(0, termCount - 1)].term;
				var curRandNum = rand.Next(10000);
				var score = (curRandNum < 10 ? rand.Next(0, 100000) : rand.Next(0, 10000));
				trie.Set(term, score, out var myPeers, out var myIndex);

				var scoreString = score.ToString();
				var iString = i.ToString();

				Console.WriteLine(new String(' ', Math.Max(0, maxTermLength - term.Length)) + term + " :" + new String(' ', Math.Max(0, 8 - scoreString.Length)) + scoreString + " :" + new String(' ', Math.Max(0, 8 - iString.Length)) + iString + " : " + (myPeers != null ? "|" : "_________"));

				if (myPeers != null) trie.verifySubtree(myPeers, myIndex);
			}
			//*/

			/*
			for (var i = 0; i < 5; i++)
				terms.Shuffle();

			for (var i = 0; i < termCount; i++)
				terms[i] = (terms[i].term, i);

			foreach (var (term, score) in terms)
				trie.Set(term, score);

			var trie2 = new PruningRadixTrie();
			trie2.AddTerms(terms, true);
			trie2.assertTreeIsTheSame(trie); // this is guaranteed to work only because all scores are unique in this test
			Console.WriteLine("Done!");
			*/
		}

		static void Main(string[] args)
		{
			Test();
		}
	}
}
