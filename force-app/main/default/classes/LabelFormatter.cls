/**
 * @description Formats a shipping label line: name in capitals, then city and state.
 */
public with sharing class LabelFormatter {
    /**
     * @description One label line.
     * @param name the recipient
     * @param city the city
     * @param state the state code
     * @return the line, for example "ANA RUIZ, Plano TX"
     */
    public static String line(String name, String city, String state) {
        return (name == null ? '' : name.trim().toUpperCase()) + ', ' + (city == null ? '' : city.trim()) + ' ' + (state == null ? '' : state.trim().toUpperCase());
    }
}