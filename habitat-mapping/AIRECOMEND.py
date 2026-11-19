from langchain_openai import ChatOpenAI
import os
import pandas as pd
from dotenv import load_dotenv
import time

# Load environment variables and set your OpenAI API key
load_dotenv()
openai_api_key = os.getenv("OPENAI_API_KEY")

# Create the ChatOpenAI instance with the "gpt-4o-mini" model
llm = ChatOpenAI(
    openai_api_key=openai_api_key,
    model="gpt-4o-mini",
    temperature=0.0,
    top_p=0.95,
    stop=None
)

def match_habitat(expert_name, expert_desc, basemap_layers, basemap_label):
    """
    Given an expert habitat name and description,
    returns a recommendation of basemap layer categories from the specified list.
    """
    prompt = f"""
You are an expert in habitat classification and spatial analysis.
I have the following expert habitat definition:

Habitat Name: "{expert_name}"
Description: "{expert_desc}"

I also have a list of basemap layer categories from a Danish basemap ({basemap_label}):
{', '.join(basemap_layers)}

Based on the above expert definition, please recommend which basemap layer categories should be combined to represent this habitat.
Provide a comma-separated list of the most appropriate basemap layer names and include a brief explanation.
"""
    result = llm.invoke(prompt)
    return result

# Load the habitat definitions from the CSV file
habitat_df = pd.read_csv("habitat_description.csv")

# Define the three basemap layer lists (update these with your actual values)
basemap_layers_C_05 = [
    "Sø", "Areal omkring bebyggelse", "Øvelsesareal", "Militære anlæg", 
    "Øvelsesareal (ubevokset_bar)", "Publikumsareal", "Skydebane", 
    "Grusgrav", "Bæltevej", "Brandbaelte", "Eng", "Strandsump", 
    "Mose", "Strandeng", "Hede", "Frit areal (overdrev)", "Slette, Overdrev (Slette)", 
    "Slette, Overdrev (overdrev)", "Klit", "Strandbred", "Ukultiveret areal", 
    "Hvidel", "Løvtræ uden særlig kode", "Ask", "Bævreasp", "Birk", 
    "Bøg", "Contorta", "Eg", "El", "Elm", "Ær", "Kirsebær", "Lind", 
    "Pil", "Poppel", "Rødeg", "Rødel", "Røn", "Krat", "Japansk lærk", 
    "Grandis", "Nåletræ uden særlig kode", "Bjergfyr", "Cypres", 
    "Douglas", "Europæisk lærk", "Frans bjergfyr", "Almindelig ædelgran", 
    "Lærk", "Nordmannsgran", "Nobilis", "Omorika", "Østrigsk fyr", 
    "Rødgran", "Sitagran", "Skovfyr", "Hvidgran", "Ager", "Slette, Overdrev (græsset)", 
    "Vildtager", "Campingplads", "Golfbane", "Park", "Ruin, gravhøj", 
    "Råstofgrav", "Brændeplads", "Marsk", "Klippe", "Skrænt", 
    "Avnbøg", "Ægte kastanie", "Hassel", "Hestekastanie", "Kristtorn", 
    "Spidsløn", "Veitchii", "Cryptomeria", "Fransk bjergfyr", "Hybridlærk", 
    "Weymouthsfyr", "Thuja", "Tsuga", "Planteskole", "Overdrev", 
    "Strandvold med enårig vegetation", "Strandvold med flerårig vegetation", 
    "Kystklint/klippe", "Enårig strandengsvegetation", "Vadegræssamfund", 
    "Indlandssalteng", "Forklit", "Hvid klit", "Grå/grøn klit", 
    "Klithede", "Havtornklit", "Grårisklit", "Skovklit", "Klitlavning", 
    "Enebærklit", "Visse-indlandsklit", "Revling-indlandsklit", 
    "Græs-indlandsklit", "Våd hede", "Tør hede", "Enekrat", "Tør overdrev på kalkholdigt sand", 
    "Kalkoverdrev", "Surt overdrev", "Tidvis våd eng", "Bræmmer med høje urter langs vandløb eller skyggende skovbryn", 
    "Højmose", "Nedbrudt højmose", "Hængesæk", "Tørvelavning", 
    "Avneknippemose", "Kildevæld", "Rigkær", "Indlandsklippe", 
    "Bøg på mor", "Bøg på mor med kristtorn", "Bøg på muld", 
    "Bøg på kalk", "Ege-blandskov", "Vinteregeskov", "Stilkege-krat", 
    "Skovbevoksede tørvemoser", "Elle- og askeskov ved vandløb, søer og væld", 
    "Rekreativt område", "Land", "Hav", "Teknisk areal", "Bassin", 
    "Skov", "Vådområde", "Sand / klit", "Havn", "Bygning", "Bykerne", 
    "Erhverv", "Lav bebyggelse", "Høj bebyggelse", "Vandloebskant", 
    "Vejmidte", "Jernbane", "Vandløbsmidte", "Startbane", "Begravelsesområde", 
    "Matrikel, vej", "Matrikel, jernbane", "Matrikel, strandbeskyttelse", 
    "Tyskland"
]

basemap_layers_C_09 = [
    "Sø", "Areal omkring bebyggelse", "Øvelsesareal", "Militære anlæg", 
    "Øvelsesareal (ubevokset_bar)", "Publikumsareal", "Skydebane", 
    "Grusgrav", "Bæltevej", "Brandbaelte", "Eng", "Strandsump", 
    "Mose", "Strandeng", "Hede", "Frit areal (overdrev)", "Slette, Overdrev (Slette)", 
    "Slette, Overdrev (overdrev)", "Klit", "Strandbred", "Ukultiveret areal", 
    "Hvidel", "Løvtræ uden særlig kode", "Ask", "Bævreasp", "Birk", 
    "Bøg", "Contorta", "Eg", "El", "Elm", "Ær", "Kirsebær", "Lind", 
    "Pil", "Poppel", "Rødeg", "Rødel", "Røn", "Krat", "Japansk lærk", 
    "Grandis", "Nåletræ uden særlig kode", "Bjergfyr", "Cypres", 
    "Douglas", "Europæisk lærk", "Frans bjergfyr", "Almindelig ædelgran", 
    "Lærk", "Nordmannsgran", "Nobilis", "Omorika", "Østrigsk fyr", 
    "Rødgran", "Sitagran", "Skovfyr", "Hvidgran", "Ager", "Slette, Overdrev (græsset)", 
    "Vildtager", "Campingplads", "Golfbane", "Park", "Ruin, gravhøj", 
    "Råstofgrav", "Brændeplads", "Marsk", "Klippe", "Skrænt", 
    "Avnbøg", "Ægte kastanie", "Hassel", "Hestekastanie", "Kristtorn", 
    "Spidsløn", "Veitchii", "Cryptomeria", "Fransk bjergfyr", "Hybridlærk", 
    "Weymouthsfyr", "Thuja", "Tsuga", "Planteskole", "Overdrev", 
    "Strandvold med enårig vegetation", "Strandvold med flerårig vegetation", 
    "Kystklint/klippe", "Enårig strandengsvegetation", "Vadegræssamfund", 
    "Indlandssalteng", "Forklit", "Hvid klit", "Grå/grøn klit", 
    "Klithede", "Havtornklit", "Grårisklit", "Skovklit", "Klitlavning", 
    "Enebærklit", "Visse-indlandsklit", "Revling-indlandsklit", 
    "Græs-indlandsklit", "Våd hede", "Tør hede", "Enekrat", "Tør overdrev på kalkholdigt sand", 
    "Kalkoverdrev", "Surt overdrev", "Tidvis våd eng", "Bræmmer med høje urter langs vandløb eller skyggende skovbryn", 
    "Højmose", "Nedbrudt højmose", "Hængesæk", "Tørvelavning", 
    "Avneknippemose", "Kildevæld", "Rigkær", "Indlandsklippe", 
    "Bøg på mor", "Bøg på mor med kristtorn", "Bøg på muld", 
    "Bøg på kalk", "Ege-blandskov", "Vinteregeskov", "Stilkege-krat", 
    "Skovbevoksede tørvemoser", "Elle- og askeskov ved vandløb, søer og væld", 
    "Rekreativt område", "Land", "Hav", "Teknisk areal, Affaldsanlæg", 
    "Teknisk areal, Genbrugsplads", "Teknisk areal, Energiforsyningsanlæg", 
    "Teknisk areal, Solenergi", "Teknisk areal, Vindmøllepark", 
    "Teknisk areal, Togstation/rangéranlæg", "Teknisk areal, Vandrensningsanlæg", 
    "Teknisk areal, Vandværk", "Teknisk areal, Rekreativt anlæg", 
    "Teknisk areal, Sportsanlæg", "Teknisk areal, Golfplads", "Teknisk areal, Landingsbane", 
    "Teknisk areal, Lufthavn", "Teknisk areal, Materielgård", "Teknisk areal, Militært anlæg", 
    "Teknisk areal, Parkeringsanlæg", "Teknisk areal, Ikke tildelt", 
    "Teknisk areal, Ukendt", "Teknisk areal, Baneterræn", "Bassin, Andet", 
    "Bassin, Ikke tildelt", "Bassin, Overløbsbassin", "Bassin, Rensningsanlæg", 
    "Bassin, Svømmebassin", "Bassin, Ukendt", "Skov", "Vådområde", 
    "Sand / klit", "Sø, Fiskedam", "Sø, Sø", "Havn", "Bygning, Bygning", 
    "Bygning, Tank/Silo", "Bygning, Husbåd", "Bygning, Drivhus", 
    "Bygning, Solpanel", "Bykerne", "Erhverv", "Lav bebyggelse", 
    "Høj bebyggelse", "Vandloebskant, >=12 m bredde", "Vejmidte, Trafikvej-Gennemfart, Befæstet, Motorvej", 
    "Vejmidte, Trafikvej-Gennemfart, Befæstet, Motortrafikvej", 
    "Vejmidte, Trafikvej-Gennemfart, Befæstet, Al færdsel", "Vejmidte, Trafikvej-Fordeling, Befæstet", 
    "Vejmidte, Lokalvej-Primær, Befæstet", "Vejmidte, Lokalvej-Sekundær, Befæstet", 
    "Vejmidte, Lokalvej-Sekundær, Ubefæstet", "Vejmidte, Lokalvej-Tertiær, Befæstet", 
    "Vejmidte, Lokalvej-Tertiær, Befæstet, Gågade", "Vejmidte, Lokalvej-Tertiær, Ubefæstet", 
    "Vejmidte, Anden vej, Befæstet", "Vejmidte, Anden vej, Befæstet, Gågade", 
    "Vejmidte, Anden vej, Ubefæstet", "Vejmidte, Indkørselsvej, Befæstet", 
    "Vejmidte, Indkørselsvej, Ubefæstet", "Jernbane, Synlig", "Vandløbsmidte, 2,5 - 12 m bredde", 
    "Vandløbsmidte, >=12 m bredde", "Startbane, Start/landing", 
    "Startbane, Taxivej", "Startbane, Plads", "Begravelsesområde", 
    "Matrikel, vej", "Matrikel, jernbane", "Matrikel, strandbeskyttelse", 
    "Tyskland"
]

basemap_layers_C_12 = [
    "Sø", "Andet bebyggelse", "Rekreativt område / sportsanlæg", 
    "Råstofudvinding", "Natur, tør", "Natur, våd", "Skov", "Landbrug, intensivt, midlertidige afgrøder", 
    "Landbrug, intensivt, permanente afgrøder", "Skov, våd", "Ikke kortlagt", 
    "Hav", "Jernbane", "Lufthavn / landingsbane", "Bygning", "Bykerne", 
    "Erhverv", "Lav bebyggelse", "Høj bebyggelse", "Vandløb", "Vej, befæstet", 
    "Vej, ikke befæstet", "Tyskland"
]

# Dictionaries to store recommendations for each basemap list
results_C_05 = {}
results_C_09 = {}
results_C_12 = {}

# Define a function to save intermediate results
def save_intermediate_results():
    df_results = pd.DataFrame({
        "Habitat": list(results_C_05.keys()),
        "C_05 Recommendation": [results_C_05[h] for h in results_C_05.keys()],
        "C_09 Recommendation": [results_C_09[h] for h in results_C_05.keys()],
        "C_12 Recommendation": [results_C_12[h] for h in results_C_05.keys()]
    })
    df_results.to_csv("habitat_layer_mapping_intermediate.csv", index=False)
    print("Intermediate results saved.")

# Iterate over each row in the CSV and query the API for each basemap list
for idx, row in habitat_df.iterrows():
    habitat_name = row["Habitat"]
    habitat_description = row["Description"]
    
    try:
        results_C_05[habitat_name] = match_habitat(habitat_name, habitat_description, basemap_layers_C_05, "C_05")
        results_C_09[habitat_name] = match_habitat(habitat_name, habitat_description, basemap_layers_C_09, "C_09")
        results_C_12[habitat_name] = match_habitat(habitat_name, habitat_description, basemap_layers_C_12, "C_12")
        print(f"Processed: {habitat_name}")
    except Exception as e:
        print(f"Error processing {habitat_name}: {e}")
    # Save after processing each habitat (you can adjust the frequency if needed)
    save_intermediate_results()
    # Optional: add a short delay to prevent rate limiting
    time.sleep(1)

# Final save (in case all habitats processed without interruption)
save_intermediate_results()
print("Mapping recommendations saved to 'habitat_layer_mapping_intermediate.xlsx'.")
