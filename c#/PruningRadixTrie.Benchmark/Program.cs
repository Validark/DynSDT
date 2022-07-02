using System;
using System.IO;
using System.Diagnostics;
using System.IO.Compression;
using System.Collections.Generic;

namespace PruningRadixTrie.Benchmark
{
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
			PruningRadixTrie pruningRadixTrie = new PruningRadixTrie();
			var numAllocatedBytes = GC.GetTotalMemory(true);
			pruningRadixTrie.ReadTermsFromFile("terms.txt");
			var numAllocatedBytes2 = GC.GetTotalMemory(true);
			Console.WriteLine("\tStructure is ~" + (numAllocatedBytes2 - numAllocatedBytes).ToString("0,,.##") + "MB.");
			pruningRadixTrie.WriteTermsToFile("terms.txt");
			Console.WriteLine("Benchmark started ...");
			int termCount = 10;
			{
				int rounds = 1000;
				string queryString = "microsoft";

				string[] prefixes = new string[queryString.Length];
				for (var i = 0; i < queryString.Length; i++) // get all prefixes of queryString
					prefixes[i] = queryString.Substring(0, i + 1);

				foreach (var prefix in prefixes) // warm up
					for (int loop = 0; loop < rounds; loop++)
						pruningRadixTrie.GetTopkTermsForPrefix(prefix, termCount);

				var powerOf1000 = 0;
				for (long freq = Stopwatch.Frequency, resolution = 1000; freq > resolution; powerOf1000++)
					resolution *= 1000;
				var tickFormatter = "0" + new string(',', powerOf1000) + ".000000";
				Stopwatch sw = new Stopwatch();
				foreach (var prefix in prefixes)
				{
					sw.Restart();
					for (int loop = 0; loop < rounds; loop++)
						pruningRadixTrie.GetTopkTermsForPrefix(prefix, termCount);
					sw.Stop();
					Console.WriteLine("queried \"" + prefix + '"' + new string(' ', queryString.Length - prefix.Length + 1) + "in " + sw.ElapsedTicks.ToString(tickFormatter) + " µs");
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

		static void Main(string[] args)
		{
			Benchmark();
		}
	}
}
